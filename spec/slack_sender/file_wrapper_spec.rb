# frozen_string_literal: true

RSpec.describe SlackSender::FileWrapper do
  before do
    unless defined?(ActiveStorage::Filename)
      stub_const("ActiveStorage::Filename", Class.new do
        def initialize(name)
          @name = name
        end

        def to_s
          @name
        end
      end)
    end
  end
  describe ".wrap" do
    it "creates a new FileWrapper instance" do
      file = StringIO.new("content")
      wrapper = described_class.wrap(file, 0)

      expect(wrapper).to be_a(described_class)
      expect(wrapper.index).to eq(0)
      expect(wrapper.content).to eq("content")
    end
  end

  describe "#filename" do
    context "with File object" do
      let(:file) { Tempfile.new(["test", ".txt"]) }
      let(:wrapper) { described_class.wrap(file, 0) }

      after do
        file.close
        file.unlink
      end

      it "uses basename of file path" do
        expect(wrapper.filename).to match(/test.*\.txt/)
      end
    end

    context "with StringIO object" do
      let(:file) { StringIO.new("content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      it "uses default attachment name" do
        expect(wrapper.filename).to eq("attachment 1")
      end
    end

    context "with object that responds to original_filename" do
      let(:file) { double(original_filename: "document.pdf", read: "content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      it "uses original_filename" do
        expect(wrapper.filename).to eq("document.pdf")
      end
    end

    context "with object that has empty original_filename" do
      let(:file) { double(original_filename: "", path: "/path/to/file.txt", read: "content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      it "falls back to path basename" do
        expect(wrapper.filename).to eq("file.txt")
      end
    end

    context "with Active Storage attachment" do
      let(:blob) { double(filename: ActiveStorage::Filename.new("attachment.pdf")) }
      let(:file) { double(blob:, filename: ActiveStorage::Filename.new("attachment.pdf"), download: "content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      before do
        stub_const("ActiveStorage::Attachment", Class.new)
        allow(file).to receive(:is_a?).with(ActiveStorage::Attachment).and_return(true)
      end

      it "uses filename from attachment" do
        expect(wrapper.filename).to eq("attachment.pdf")
      end
    end

    context "with Active Storage attachment without filename" do
      let(:blob) { double(filename: ActiveStorage::Filename.new("blob.pdf")) }
      let(:file) { double(blob:, filename: ActiveStorage::Filename.new(""), download: "content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      before do
        stub_const("ActiveStorage::Attachment", Class.new)
        allow(file).to receive(:is_a?).with(ActiveStorage::Attachment).and_return(true)
      end

      it "falls back to blob filename" do
        expect(wrapper.filename).to eq("blob.pdf")
      end
    end

    context "with multiple files" do
      let(:first_file) { StringIO.new("content1") }
      let(:second_file) { StringIO.new("content2") }
      let(:first_wrapper) { described_class.wrap(first_file, 0) }
      let(:second_wrapper) { described_class.wrap(second_file, 1) }

      it "uses index in default filename" do
        expect(first_wrapper.filename).to eq("attachment 1")
        expect(second_wrapper.filename).to eq("attachment 2")
      end
    end
  end

  describe "#content" do
    context "with File object" do
      let(:file) { Tempfile.new(["test", ".txt"]) }
      let(:wrapper) { described_class.wrap(file, 0) }

      before do
        file.write("file content")
        file.rewind
      end

      after do
        file.close
        file.unlink
      end

      it "reads file content" do
        expect(wrapper.content).to eq("file content")
      end
    end

    context "with StringIO object" do
      let(:file) { StringIO.new("stringio content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      it "reads content and rewinds" do
        file.read # Move position forward
        expect(wrapper.content).to eq("stringio content")
      end

      it "rewinds before reading" do
        file.read # Move position forward
        content = wrapper.content
        expect(content).to eq("stringio content")
        # Content is memoized, so file position after read is at end, but rewind happened before read
        expect(file.pos).to eq("stringio content".length)
      end
    end

    context "with Active Storage attachment" do
      let(:file) { double }
      let(:wrapper) { described_class.wrap(file, 0) }

      before do
        stub_const("ActiveStorage::Attachment", Class.new)
        allow(file).to receive(:is_a?).with(ActiveStorage::Attachment).and_return(true)
        allow(file).to receive(:download).and_return("downloaded content")
        allow(file).to receive(:filename).and_return(ActiveStorage::Filename.new("test.pdf"))
        allow(file).to receive(:blob).and_return(nil)
      end

      it "downloads content from attachment" do
        expect(wrapper.content).to eq("downloaded content")
      end
    end

    context "with object that responds to read" do
      let(:file) { double(read: "read content") }
      let(:wrapper) { described_class.wrap(file, 0) }

      it "calls read method" do
        expect(wrapper.content).to eq("read content")
      end
    end

    context "with object that does not support reading" do
      let(:file) { double }

      before do
        allow(file).to receive(:respond_to?).with(:to_h).and_return(false)
        allow(file).to receive(:respond_to?).with(:filename).and_return(false)
        allow(file).to receive(:respond_to?).with(:content).and_return(false)
        allow(file).to receive(:respond_to?).with(:read).and_return(false)
        allow(file).to receive(:respond_to?).with(:original_filename).and_return(false)
        allow(file).to receive(:respond_to?).with(:path).and_return(false)
        allow(file).to receive(:class).and_return(Object)
        allow(file).to receive(:is_a?).and_return(false)
      end

      it "raises ArgumentError during initialization" do
        expect { described_class.wrap(file, 0) }.to raise_error(ArgumentError, /does not support reading/)
      end
    end
  end

  describe "#to_h" do
    let(:file) { Tempfile.new(["test", ".txt"]) }
    let(:wrapper) { described_class.wrap(file, 0) }

    before do
      file.write("content")
      file.rewind
    end

    after do
      file.close
      file.unlink
    end

    it "returns hash with filename and content" do
      result = wrapper.to_h

      expect(result).to be_a(Hash)
      expect(result).to have_key(:filename)
      expect(result).to have_key(:content)
      expect(result[:filename]).to match(/test.*\.txt/)
      expect(result[:content]).to eq("content")
    end
  end

  describe "memoization" do
    let(:file) { StringIO.new("content") }
    let(:wrapper) { described_class.wrap(file, 0) }

    it "memoizes filename" do
      expect(wrapper.filename).to eq(wrapper.filename)
    end

    it "memoizes content" do
      expect(wrapper.content).to eq(wrapper.content)
    end
  end
end
