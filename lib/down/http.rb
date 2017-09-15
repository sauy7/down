# frozen-string-literal: true

require "http"

require "down/backend"

require "tempfile"
require "cgi"
require "base64"

if Gem::Version.new(HTTP::VERSION) < Gem::Version.new("2.1.0")
  fail "Down requires HTTP.rb version 2.1.0 or higher"
end

module Down
  class Http < Backend
    def initialize(client_or_options = nil)
      options = client_or_options
      options = client_or_options.default_options if client_or_options.is_a?(HTTP::Client)

      @client = HTTP.headers("User-Agent" => "Down/#{Down::VERSION}").follow(max_hops: 2)
      @client = HTTP::Client.new(@client.default_options.merge(options)) if options
    end

    def download(url, max_size: nil, progress_proc: nil, content_length_proc: nil, **options, &block)
      io = open(url, **options, rewindable: false, &block)

      content_length_proc.call(io.size) if content_length_proc && io.size

      if max_size && io.size && io.size > max_size
        raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
      end

      extname  = File.extname(io.data[:response].uri.path)
      tempfile = Tempfile.new(["down-http", extname], binmode: true)

      until io.eof?
        tempfile.write(io.readpartial)

        progress_proc.call(tempfile.size) if progress_proc

        if max_size && tempfile.size > max_size
          raise Down::TooLarge, "file is too large (max is #{max_size/1024/1024}MB)"
        end
      end

      tempfile.open # flush written content

      tempfile.extend Down::Http::DownloadedFile
      tempfile.url     = io.data[:response].uri.to_s
      tempfile.headers = io.data[:headers]

      tempfile
    rescue
      tempfile.close! if tempfile
      raise
    ensure
      io.close if io
    end

    def open(url, rewindable: true, **options, &block)
      response = get(url, **options, &block)

      response_error!(response) if !response.status.success?

      body_chunks = Enumerator.new do |yielder|
        begin
          response.body.each { |chunk| yielder << chunk }
        rescue => exception
          request_error!(exception)
        end
      end

      Down::ChunkedIO.new(
        chunks:     body_chunks,
        size:       response.content_length,
        encoding:   response.content_type.charset,
        rewindable: rewindable,
        on_close:   (-> { response.connection.close } unless @client.persistent?),
        data:       { status: response.code, headers: response.headers.to_h, response: response },
      )
    rescue => exception
      request_error!(exception)
    end

    private

    def get(url, **options, &block)
      uri = HTTP::URI.parse(url)

      if uri.user || uri.password
        user, pass = uri.user, uri.password
        authorization = "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"
        (options[:headers] ||= {}).merge!("Authorization" => authorization)
        uri.user = uri.password = nil
      end

      client = @client
      client = block.call(client) if block
      client.get(url, options)
    end

    def response_error!(response)
      args = [response.status.to_s, response: response]

      case response.code
        when 400..499 then raise Down::ClientError.new(*args)
        when 500..599 then raise Down::ServerError.new(*args)
        else               raise Down::ResponseError.new(*args)
      end
    end

    def request_error!(exception)
      case exception
        when HTTP::Request::UnsupportedSchemeError
          raise Down::InvalidUrl, exception.message
        when Errno::ECONNREFUSED
          raise Down::ConnectionError, "connection was refused"
        when HTTP::ConnectionError,
          Errno::ECONNABORTED,
          Errno::ECONNRESET,
          Errno::EPIPE,
          Errno::EINVAL,
          Errno::EHOSTUNREACH
          raise Down::ConnectionError, exception.message
        when SocketError
          raise Down::ConnectionError, "domain name could not be resolved"
        when HTTP::TimeoutError
          raise Down::TimeoutError, exception.message
        when HTTP::Redirector::TooManyRedirectsError
          raise Down::TooManyRedirects, exception.message
        when defined?(OpenSSL) && OpenSSL::SSL::SSLError
          raise Down::SSLError, exception.message
        else
          raise exception
      end
    end

    module DownloadedFile
      attr_accessor :url, :headers

      def original_filename
        filename_from_content_disposition || filename_from_url
      end

      def content_type
        content_type_header.mime_type
      end

      def charset
        content_type_header.charset
      end

      private

      def content_type_header
        ::HTTP::ContentType.parse(headers["Content-Type"])
      end

      def filename_from_content_disposition
        content_disposition = headers["Content-Disposition"].to_s
        filename = content_disposition[/filename="([^"]*)"/, 1] || content_disposition[/filename=(.+)/, 1]
        filename = CGI.unescape(filename.to_s.strip)
        filename unless filename.empty?
      end

      def filename_from_url
        path = URI(url).path
        filename = path.split("/").last
        CGI.unescape(filename) if filename
      end
    end
  end
end
