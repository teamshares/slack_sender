# frozen_string_literal: true

module SlackSender
  # Handles synchronous upload of files to Slack's servers without sharing them.
  # Returns file_ids that can be serialized and passed to a background job,
  # which then calls files_completeUploadExternal to share the files to a channel.
  #
  # This enables async file uploads by separating the upload phase (sync, in caller's thread)
  # from the share phase (async, in background job).
  class FileUploader
    attr_reader :client, :files

    def initialize(client, raw_files)
      @client = client
      @files = MultiFileWrapper.new(raw_files).files
    end

    # Uploads files to Slack's servers without sharing them to any channel.
    # Returns an array of hashes with :id and :title keys, suitable for
    # passing to files_completeUploadExternal.
    #
    # @return [Array<Hash>] Array of { id: String, title: String }
    # @raise [Slack::Web::Api::Errors::SlackError] If upload fails
    def upload_to_slack
      files.map do |file|
        response = client.files_getUploadURLExternal(
          filename: file.filename,
          length: file.content.bytesize,
        )

        upload_file_content(response["upload_url"], file.content)

        { "id" => response["file_id"], "title" => file.filename }
      end
    end

    private

    # POSTs file content to Slack's upload URL.
    # This mimics what slack-ruby-client does internally in files_upload_v2.
    def upload_file_content(upload_url, content)
      connection = build_upload_connection(upload_url)
      response = connection.post { |req| req.body = content }

      # The upload endpoint returns 200 on success
      return if response.success?

      raise Error, "Failed to upload file to Slack: #{response.status} - #{response.body}"
    end

    def build_upload_connection(upload_url)
      ::Faraday::Connection.new(upload_url) do |conn|
        conn.request :multipart
        conn.request :url_encoded
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
