# frozen_string_literal: true

module SlackSender
  class MultiFileWrapper
    attr_reader :files

    def initialize(raw_files)
      files_array = case raw_files
                    when Array then raw_files
                    when nil then []
                    else [raw_files]
                    end
      @files = files_array.presence&.each_with_index&.map { |f, i| FileWrapper.wrap(f, i) } || []
    end

    def total_file_size
      files.sum { |f| f.content.bytesize }.to_i
    end

    # Validates files for async upload constraints.
    # Raises SlackSender::Error if validation fails.
    def validate_for_async!
      validate_individual_file_sizes!
      validate_total_async_size!
    end

    private

    # Validates each file against Slack's hard limit (1 GB per file)
    def validate_individual_file_sizes!
      max_size = Configuration::SLACK_MAX_FILE_SIZE
      files.each do |file|
        next unless file.content.bytesize > max_size

        raise Error, format(ErrorMessages::FILE_EXCEEDS_SLACK_LIMIT, file.filename, file.content.bytesize)
      end
    end

    # Validates total size against async limit to avoid blocking web processes
    def validate_total_async_size!
      max_async_size = SlackSender.config.max_async_file_upload_size
      return if max_async_size.nil? # nil means disabled

      return unless total_file_size > max_async_size

      raise Error, format(ErrorMessages::FILES_EXCEED_ASYNC_LIMIT, total_file_size, max_async_size)
    end
  end
end
