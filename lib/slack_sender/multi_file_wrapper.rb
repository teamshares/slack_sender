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
                    elsif FileWrapper.file_like?(raw_files)
                      [raw_files]
                    else
                      Array(raw_files)
                    end
      @files = files_array.presence&.each_with_index&.map { |f, i| FileWrapper.wrap(f, i) } || []
    end

    def total_file_size
      files.sum { |f| f.content.bytesize }.to_i
    end
  end
end
