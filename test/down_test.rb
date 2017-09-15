require "test_helper"

require "down"
require "down/http"

describe Down do
  i_suck_and_my_tests_are_order_dependent! # ಠ_ಠ

  describe "#backend" do
    it "returns NetHttp by default" do
      assert_equal Down::NetHttp, Down.backend
    end

    it "can set the backend via a symbol" do
      Down.backend :http
      assert_equal Down::Http, Down.backend
    end

    it "can set the backend via a class" do
      Down.backend Down::Http
      assert_equal Down::Http, Down.backend
    end
  end

  describe "#download" do
    it "delegates to the underlying backend" do
      Down.backend.expects(:download).with("http://example.com")
      Down.download("http://example.com")
    end
  end

  describe "#open" do
    it "delegates to the underlying backend" do
      Down.backend.expects(:open).with("http://example.com")
      Down.open("http://example.com")
    end
  end
end

=begin
require "test_helper"
require "stringio"

describe Down do
  describe "#download" do
    it "downloads url to disk" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_instance_of Tempfile, tempfile
      assert File.exist?(tempfile.path)
    end

    it "works with query parameters" do
      stub_request(:get, "http://example.com/image.jpg?foo=bar")
      Down.download("http://example.com/image.jpg?foo=bar")
    end

    it "converts small StringIOs to tempfiles" do
      stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/small.jpg")
      assert_instance_of Tempfile, tempfile
      assert File.exist?(tempfile.path)
      assert_equal "aaaaa", tempfile.read
    end

    it "accepts max size" do
      # "Content-Length" header
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      assert_raises(Down::TooLarge) { Down.download("http://example.com/image.jpg", max_size: 4) }

      # no "Content-Length" header
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      assert_raises(Down::TooLarge) { Down.download("http://example.com/image.jpg", max_size: 4) }

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      tempfile = Down.download("http://example.com/image.jpg", max_size: 6)
      assert File.exist?(tempfile.path)
    end

    it "accepts :progress_proc and :content_length_proc" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => 5})
      Down.download "http://example.com/image.jpg",
        content_length_proc: ->(n) { @content_length = n },
        progress_proc:       ->(n) { @progress = n }
      assert_equal 5, @content_length
      assert_equal 5, @progress
    end

    it "adds #content_type to downloaded files" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024, headers: {'Content-Type' => 'image/jpeg'})
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "image/jpeg", tempfile.content_type

      stub_request(:get, "http://example.com/small.jpg").to_return(body: "a" * 5, headers: {'Content-Type' => 'image/jpeg'})
      tempfile = Down.download("http://example.com/small.jpg")
      assert_equal "image/jpeg", tempfile.content_type
    end

    it "adds #original_filename extracted from Content-Disposition" do
      stub_request(:get, "http://example.com/foo.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'filename="my filename.ext"'})
      tempfile = Down.download("http://example.com/foo.jpg")
      assert_equal "my filename.ext", tempfile.original_filename

      stub_request(:get, "http://example.com/bar.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'filename="my%20filename.ext"'})
      tempfile = Down.download("http://example.com/bar.jpg")
      assert_equal "my filename.ext", tempfile.original_filename

      stub_request(:get, "http://example.com/baz.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'filename=myfilename.ext '})
      tempfile = Down.download("http://example.com/baz.jpg")
      assert_equal "myfilename.ext", tempfile.original_filename
    end

    it "adds #original_filename extracted from URI path if Content-Disposition is blank" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "image.jpg", tempfile.original_filename

      stub_request(:get, "http://example.com/image%20space%2Fslash.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/image%20space%2Fslash.jpg")
      assert_equal "image space/slash.jpg", tempfile.original_filename

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Disposition' => 'inline; filename='})
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "image.jpg", tempfile.original_filename

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Disposition' => 'inline; filename=""'})
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal "image.jpg", tempfile.original_filename

      stub_request(:get, "http://example.com").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com")
      assert_nil tempfile.original_filename

      stub_request(:get, "http://example.com/").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/")
      assert_nil tempfile.original_filename
    end

    it "keep_original_filename option uses the original filename for the tempfile" do
      # from content-disposition
      stub_request(:get, "http://example.com/image.jpg")
        .to_return(body: "a" * 5, headers: {'Content-Disposition' => 'attachment; filename=myfilename.foo '})

      tempfile = Down.download("http://example.com/image.jpg", keep_original_filename: true)
      assert_match /myfilename[^.]+\.foo/, tempfile.path
      assert_equal "myfilename.foo", tempfile.original_filename

      # from url, where content-disposition is missing
      stub_request(:get, "http://example.com/image.jpg")
        .to_return(body: "a" * 5)

      tempfile = Down.download("http://example.com/image.jpg", keep_original_filename: true)
      assert_match /image[^.]+\.jpg/, tempfile.path
      assert_equal "image.jpg", tempfile.original_filename
    end

    it "preserves extension" do
      # Tempfile
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 20 * 1024)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal ".jpg", File.extname(tempfile.path)
      assert File.exist?(tempfile.path)

      # StringIO
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      tempfile = Down.download("http://example.com/image.jpg")
      assert_equal ".jpg", File.extname(tempfile.path)
      assert File.exist?(tempfile.path)
    end

    it "raises NotFound on HTTP errors" do
      stub_request(:get, "http://example.com").to_return(status: 404)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }

      stub_request(:get, "http://example.com").to_return(status: 500)
      assert_raises(Down::NotFound) { Down.download("http://example.com") }
    end

    it "raises on invalid URL" do
      assert_raises(Down::Error) { Down.download("http:\\example.com/image.jpg") }
    end

    it "raises on invalid scheme" do
      assert_raises(Down::Error) { Down.download("foo://example.com/image.jpg") }
    end

    it "doesn't allow shell execution" do
      assert_raises(Down::Error) { Down.download("| ls") }
    end
  end

  describe "#stream" do
    it "calls the block with downloaded chunks" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => '5'})
      chunks = Down.enum_for(:stream, "http://example.com/image.jpg").to_a
      refute_empty chunks
      assert_equal "aaaaa", chunks.map(&:first).join
      assert_equal 5, chunks.first.last
    end

    it "yields nil for content length if header is not present" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "a" * 5)
      chunks = Down.enum_for(:stream, "http://example.com/image.jpg").to_a
      assert_equal nil, chunks.first.last
    end

    it "handles HTTPS links" do
      stub_request(:get, "https://example.com/image.jpg").to_return(body: "a" * 5, headers: {'Content-Length' => '5'})
      chunks = Down.enum_for(:stream, "https://example.com/image.jpg").to_a
      refute_empty chunks
      assert_equal "aaaaa", chunks.map(&:first).join
      assert_equal 5, chunks.first.last
    end
  end

  describe "#open" do
    it "assigns chunks from response body" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      assert_equal "abc", io.read
    end

    it "works with query parameters" do
      stub_request(:get, "http://example.com/image.jpg?foo=bar")
      Down.open("http://example.com/image.jpg?foo=bar")
    end

    it "extracts size from Content-Length" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Content-Length' => 3})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 3, io.size

      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      assert_equal nil, io.size
    end

    it "works around chunked Transfer-Encoding response" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc", headers: {'Transfer-Encoding' => 'chunked'})
      io = Down.open("http://example.com/image.jpg")
      assert_equal 3, io.size
      assert_equal "abc", io.read
    end

    it "closes connection on #close" do
      stub_request(:get, "http://example.com/image.jpg").to_return(body: "abc")
      io = Down.open("http://example.com/image.jpg")
      Net::HTTP.any_instance.expects(:do_finish)
      io.close
    end
  end

  describe "#copy_to_tempfile" do
    it "returns a tempfile" do
      tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))
      assert_instance_of Tempfile, tempfile
    end

    it "rewinds IOs" do
      io = StringIO.new("foo")
      tempfile = Down.copy_to_tempfile("foo", io)
      assert_equal "foo", io.read
      assert_equal "foo", tempfile.read
    end

    it "opens in binmode" do
      tempfile = Down.copy_to_tempfile("foo", StringIO.new("foo"))
      assert tempfile.binmode?
    end

    it "accepts basenames to be nested paths" do
      tempfile = Down.copy_to_tempfile("foo/bar/baz", StringIO.new("foo"))
      assert File.exist?(tempfile.path)
    end

    it "preserves extension" do
      tempfile = Down.copy_to_tempfile("foo.jpg", StringIO.new("foo"))
      assert_equal ".jpg", File.extname(tempfile.path)
    end
  end
end
=end
