# frozen_string_literal: true

module Utils
  class StatusService
    VERSION_FILE = 'LAGO_VERSIONS'
    GITHUB_BASE_URL = 'https://github.com/getlago/lago'

    def version
      result.version = OpenStruct.new(
        number: version_number,
        github_url: github_url,
      )
      result
    end

    private

    def version_number
      return release_date if git_hash?

      file_content
    rescue Errno::ENOENT
      Rails.env
    end

    def github_url
      "#{GITHUB_TAG_BASE_URL}/tree/#{file_content}"
    rescue Errno::ENOENT
      GITHUB_TAG_BASE_URL
    end

    def file_content
      @file_content ||= File.read(LAGO_VERSIONS).chop
    end

    def release_date
      File.ctime(VERSION_FILE)
    end

    def git_hash?
      file_content&.size == 40
    end
  end
end
