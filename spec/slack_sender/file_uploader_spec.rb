# frozen_string_literal: true

RSpec.describe SlackSender::FileUploader do
  let(:profile) { build(:profile) }
  let(:client) { instance_double(Slack::Web::Client) }
  let(:file_content) { "test file content" }
  let(:file) { StringIO.new(file_content) }

  before do
    allow(profile).to receive(:client).and_return(client)
  end

  describe "#initialize" do
    it "wraps files using MultiFileWrapper" do
      uploader = described_class.new(client, file)

      expect(uploader.files).to be_an(Array)
      expect(uploader.files.length).to eq(1)
      expect(uploader.files.first).to be_a(SlackSender::FileWrapper)
    end

    it "handles array of files" do
      file2 = StringIO.new("second file")
      uploader = described_class.new(client, [file, file2])

      expect(uploader.files.length).to eq(2)
    end
  end

  describe "#upload_to_slack" do
    let(:upload_url) { "https://files.slack.com/upload/v1/ABC123" }
    let(:file_id) { "F123ABC456" }
    let(:faraday_connection) { instance_double(Faraday::Connection) }
    let(:faraday_response) { instance_double(Faraday::Response, success?: true, status: 200) }

    before do
      allow(client).to receive(:files_getUploadURLExternal).and_return({
                                                                         "upload_url" => upload_url,
                                                                         "file_id" => file_id,
                                                                       })
      allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
      allow(faraday_connection).to receive(:post).and_yield(double(body: nil).as_null_object).and_return(faraday_response)
    end

    it "calls files_getUploadURLExternal with filename and length" do
      uploader = described_class.new(client, file)

      expect(client).to receive(:files_getUploadURLExternal).with(
        filename: "attachment 1",
        length: file_content.bytesize,
      )

      uploader.upload_to_slack
    end

    it "POSTs file content to the upload URL" do
      uploader = described_class.new(client, file)

      expect(Faraday::Connection).to receive(:new).with(upload_url).and_return(faraday_connection)
      expect(faraday_connection).to receive(:post).and_return(faraday_response)

      uploader.upload_to_slack
    end

    it "returns array of file info hashes with id and title" do
      uploader = described_class.new(client, file)

      result = uploader.upload_to_slack

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first).to eq({ "id" => file_id, "title" => "attachment 1" })
    end

    context "with multiple files" do
      let(:file2) { StringIO.new("second file content") }
      let(:file_id2) { "F789DEF012" }

      before do
        call_count = 0
        allow(client).to receive(:files_getUploadURLExternal) do
          call_count += 1
          {
            "upload_url" => "#{upload_url}/#{call_count}",
            "file_id" => call_count == 1 ? file_id : file_id2,
          }
        end
      end

      it "uploads each file and returns all file info" do
        uploader = described_class.new(client, [file, file2])

        result = uploader.upload_to_slack

        expect(result.length).to eq(2)
        expect(result[0]["id"]).to eq(file_id)
        expect(result[1]["id"]).to eq(file_id2)
      end
    end

    context "with named file" do
      let(:named_file) do
        f = StringIO.new("named content")
        f.define_singleton_method(:original_filename) { "report.csv" }
        f
      end

      it "uses the original filename in the title" do
        uploader = described_class.new(client, named_file)

        expect(client).to receive(:files_getUploadURLExternal).with(
          filename: "report.csv",
          length: "named content".bytesize,
        )

        result = uploader.upload_to_slack

        expect(result.first["title"]).to eq("report.csv")
      end
    end

    context "when upload fails" do
      let(:failed_response) { instance_double(Faraday::Response, success?: false, status: 500, body: "Internal Server Error") }

      before do
        allow(faraday_connection).to receive(:post).and_return(failed_response)
      end

      it "raises an error" do
        uploader = described_class.new(client, file)

        expect { uploader.upload_to_slack }.to raise_error(
          SlackSender::Error,
          /Failed to upload file to Slack: 500/,
        )
      end
    end

    context "when files_getUploadURLExternal fails" do
      before do
        allow(client).to receive(:files_getUploadURLExternal).and_raise(
          Slack::Web::Api::Errors::SlackError.new("ratelimited"),
        )
      end

      it "propagates the error" do
        uploader = described_class.new(client, file)

        expect { uploader.upload_to_slack }.to raise_error(Slack::Web::Api::Errors::SlackError)
      end
    end
  end
end
