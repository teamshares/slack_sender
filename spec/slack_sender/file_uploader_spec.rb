# frozen_string_literal: true

RSpec.describe SlackSender::FileUploader do
  let(:client) { instance_double(Slack::Web::Client) }
  let(:file_content) { "test file content" }
  let(:file) { StringIO.new(file_content) }
  let(:wrapped_files) { SlackSender::MultiFileWrapper.new(file).files }

  describe "#initialize" do
    it "stores the provided files" do
      uploader = described_class.new(client, wrapped_files)

      expect(uploader.files).to eq(wrapped_files)
      expect(uploader.files.first).to be_a(SlackSender::FileWrapper)
    end

    it "stores the client" do
      uploader = described_class.new(client, wrapped_files)

      expect(uploader.client).to eq(client)
    end
  end

  describe "#upload_to_slack" do
    subject(:uploader) { described_class.new(client, wrapped_files) }

    let(:upload_url) { "https://files.slack.com/upload/v1/ABC123" }
    let(:file_id) { "F123ABC456" }
    let(:faraday_connection) { instance_double(Faraday::Connection) }
    let(:upload_response) { instance_double(Faraday::Response, success?: true, status: 200) }

    before do
      allow(client).to receive(:files_getUploadURLExternal).and_return({
                                                                         "upload_url" => upload_url,
                                                                         "file_id" => file_id,
                                                                       })
      allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
      allow(faraday_connection).to receive(:post).and_yield(double(body: nil).as_null_object).and_return(upload_response)
    end

    it "calls files_getUploadURLExternal with filename and length" do
      expect(client).to receive(:files_getUploadURLExternal).with(
        filename: "attachment 1",
        length: file_content.bytesize,
      )

      uploader.upload_to_slack
    end

    it "POSTs file content to the upload URL" do
      expect(Faraday::Connection).to receive(:new).with(upload_url).and_return(faraday_connection)
      expect(faraday_connection).to receive(:post).and_return(upload_response)

      uploader.upload_to_slack
    end

    it "returns array of file info hashes with id and title" do
      result = uploader.upload_to_slack

      expect(result).to eq([{ "id" => file_id, "title" => "attachment 1" }])
    end

    context "with multiple files" do
      let(:file2) { StringIO.new("second file content") }
      let(:wrapped_files) { SlackSender::MultiFileWrapper.new([file, file2]).files }
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
        result = uploader.upload_to_slack

        expect(result).to eq([
                               { "id" => file_id, "title" => "attachment 1" },
                               { "id" => file_id2, "title" => "attachment 2" },
                             ])
      end
    end

    context "with named file" do
      let(:named_file) do
        f = StringIO.new("named content")
        f.define_singleton_method(:original_filename) { "report.csv" }
        f
      end
      let(:wrapped_files) { SlackSender::MultiFileWrapper.new(named_file).files }

      it "uses the original filename" do
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

      before { allow(faraday_connection).to receive(:post).and_return(failed_response) }

      it "raises an error with status code" do
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

      it "propagates the Slack error" do
        expect { uploader.upload_to_slack }.to raise_error(Slack::Web::Api::Errors::SlackError)
      end
    end

    context "when MissingScope error occurs" do
      let(:response_body) { double("body", error: "missing_scope", errors: nil, needed: "files:write", response_metadata: nil) }
      let(:response_env) { { request_headers: {}, response_headers: {} } }
      let(:trigger_error) { -> { uploader.upload_to_slack } }

      before { allow(client).to receive(:files_getUploadURLExternal).and_raise(missing_scope_error) }

      include_examples "missing scope error handling", expected_scope: "files:write"

      context "when needed scope is in response_metadata" do
        include_examples "missing scope error extraction from response_metadata", expected_scope: "files:read"
      end

      context "when needed scope is only in HTTP headers" do
        include_examples "missing scope error extraction from HTTP headers", expected_scope: "files:write"
      end

      context "when no scope information is available" do
        include_examples "missing scope error with unknown scope"
      end
    end
  end
end
