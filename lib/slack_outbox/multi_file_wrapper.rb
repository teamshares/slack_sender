# frozen_string_literal: true

module SlackOutbox
  class MultiFileWrapper
    attr_reader :files

    def initialize(raw_files)
      @files = Array(raw_files).presence&.each_with_index&.map { |f, i| FileWrapper.wrap(f, i) } || []
    end

    def total_file_size
      files.sum { |f| f.content.bytesize }.to_i
    end
  end
end
