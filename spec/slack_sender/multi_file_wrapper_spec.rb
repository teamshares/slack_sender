# frozen_string_literal: true

RSpec.describe SlackSender::MultiFileWrapper do
  describe "#initialize" do
    context "with array of files" do
      let(:file1) { StringIO.new("content one") }
      let(:file2) { StringIO.new("content two") }
      let(:wrapper) { described_class.new([file1, file2]) }

      it "wraps all files" do
        expect(wrapper.files.length).to eq(2)
        expect(wrapper.files).to all(be_a(SlackSender::FileWrapper))
      end

      it "assigns correct indices" do
        expect(wrapper.files[0].index).to eq(0)
        expect(wrapper.files[1].index).to eq(1)
      end
    end

    context "with single file (non-array)" do
      let(:file) { StringIO.new("single content") }
      let(:wrapper) { described_class.new(file) }

      it "wraps the single file into an array" do
        expect(wrapper.files.length).to eq(1)
        expect(wrapper.files.first).to be_a(SlackSender::FileWrapper)
      end
    end

    context "with nil" do
      let(:wrapper) { described_class.new(nil) }

      it "returns empty files array" do
        expect(wrapper.files).to eq([])
      end
    end

    context "with empty array" do
      let(:wrapper) { described_class.new([]) }

      it "returns empty files array" do
        expect(wrapper.files).to eq([])
      end
    end
  end

  describe "#total_file_size" do
    context "with multiple files" do
      let(:file1) { StringIO.new("hello") } # 5 bytes
      let(:file2) { StringIO.new("world!!") } # 7 bytes
      let(:wrapper) { described_class.new([file1, file2]) }

      it "sums the bytesize of all file contents" do
        expect(wrapper.total_file_size).to eq(12)
      end
    end

    context "with single file" do
      let(:file) { StringIO.new("test content") } # 12 bytes
      let(:wrapper) { described_class.new(file) }

      it "returns the bytesize of the single file" do
        expect(wrapper.total_file_size).to eq(12)
      end
    end

    context "with empty files array" do
      let(:wrapper) { described_class.new([]) }

      it "returns 0" do
        expect(wrapper.total_file_size).to eq(0)
      end
    end

    context "with nil" do
      let(:wrapper) { described_class.new(nil) }

      it "returns 0" do
        expect(wrapper.total_file_size).to eq(0)
      end
    end

    context "with multibyte characters" do
      let(:file) { StringIO.new("日本語") } # 9 bytes in UTF-8
      let(:wrapper) { described_class.new(file) }

      it "returns bytesize not character count" do
        expect(wrapper.total_file_size).to eq(9)
      end
    end

    context "with binary content" do
      # Use binary content without null bytes to avoid File.exist? path check issues
      let(:file) { StringIO.new("\xFF\xFE\x01\x02\x03".b) } # 5 bytes
      let(:wrapper) { described_class.new(file) }

      it "counts binary bytes correctly" do
        expect(wrapper.total_file_size).to eq(5)
      end
    end
  end
end
