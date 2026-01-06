# frozen_string_literal: true

module SlackSender
  class FileWrapper
    attr_reader :index

    def self.wrap(file, index)
      # If it's already a FileWrapper, return it as-is
      return file if file.instance_of?(self)

      # If it's a string file path, open it first
      file = File.open(file) if file.instance_of?(String) && File.exist?(file)

      new(file, index)
    end

    def initialize(file, index)
      @index = index
      # Read content and filename immediately to avoid Sidekiq serialization issues
      # (File objects can't be serialized for async jobs)
      @filename = detect_filename(file)
      @content = read_content(file)
    end

    def filename
      @filename || "attachment #{index + 1}"
    end

    def content
      @content || ""
    end

    def to_h
      { filename:, content: }
    end

    private

    def detect_filename(file)
      if active_storage_attachment?(file)
        file.filename.to_s.presence || file.blob&.filename.to_s.presence
      elsif file.respond_to?(:original_filename) && file.original_filename.present?
        file.original_filename
      elsif file.respond_to?(:path) && file.path.present?
        File.basename(file.path)
      else
        "attachment #{index + 1}"
      end
    end

    def read_content(file)
      if active_storage_attachment?(file)
        file.download
      elsif stringio?(file)
        file.rewind
        file.read
      elsif file.is_a?(File) || file.is_a?(Tempfile)
        file.rewind if file.respond_to?(:rewind)
        file.read
      elsif file.respond_to?(:read)
        file.read
      elsif file.is_a?(String)
        # Handle case where file content is already a string
        # (e.g., if File object was converted to string content somehow)
        file
      else
        raise ArgumentError, "File object does not support reading: #{file.class}"
      end
    end

    def active_storage_attachment?(file)
      defined?(ActiveStorage::Attachment) && file.is_a?(ActiveStorage::Attachment)
    end

    def stringio?(file)
      file.is_a?(StringIO)
    end
  end
end
