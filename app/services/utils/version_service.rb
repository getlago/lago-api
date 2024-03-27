# frozen_string_literal: true

module Utils
  class VersionService < BaseService
    VERSION_FILE = Rails.root.join("LAGO_VERSION")
    GITHUB_BASE_URL = "https://github.com/getlago/lago-api"

    def version
      result.version = OpenStruct.new(
        number: version_number,
        github_url:
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
      "#{GITHUB_BASE_URL}/tree/#{file_content}"
    rescue Errno::ENOENT
      GITHUB_BASE_URL
    end

    def file_content
      @file_content ||= File.read(VERSION_FILE).squish
    end

    def release_date
      File.ctime(VERSION_FILE).to_date.iso8601
    end

    def git_hash?
      file_content&.size == 40
    end
  end
end
