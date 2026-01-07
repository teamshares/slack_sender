# frozen_string_literal: true

module SlackSender
  class MultiFileWrapper
    attr_reader :files

    def initialize(raw_files)
      # If it's already an array, use it as-is
      # If it's a single file-like object, wrap it in an array
      # Otherwise, try Array() conversion (but this should be rare)
      files_array = if raw_files.is_a?(Array)
                      raw_files
                    elsif file_like_object?(raw_files)
                      [raw_files]
                    else
                      Array(raw_files)
                    end
      @files = files_array.presence&.each_with_index&.map { |f, i| FileWrapper.wrap(f, i) } || []
    end

    def total_file_size
      files.sum { |f| f.content.bytesize }.to_i
    end

    private

    def file_like_object?(obj)
      return false if obj.nil?
      return true if obj.is_a?(StringIO)
      return true if obj.is_a?(File) || obj.is_a?(Tempfile)
      return true if defined?(ActiveStorage::Attachment) && obj.is_a?(ActiveStorage::Attachment)
      return true if obj.respond_to?(:read) && (obj.respond_to?(:original_filename) || obj.respond_to?(:path))

      false
    end
  end
end
