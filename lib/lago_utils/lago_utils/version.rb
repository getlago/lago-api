# frozen_string_literal: true

module LagoUtils
  class Version
    VERSION_FILE = Rails.root.join("LAGO_VERSION")
    GITHUB_BASE_URL = "https://github.com/getlago/lago-api"

    Result = Data.define(:number, :github_url, :sha) do
      def sha_or_number
        sha || number
      end
    end

    class << self
      def call(default:)
        Result.new(version_number(default:), github_url, sha)
      end

      private

      def sha
        file_content if git_hash?
      rescue Errno::ENOENT
        nil
      end

      def version_number(default:)
        return release_date if git_hash?

        file_content
      rescue Errno::ENOENT
        default
      end

      def github_url
        "#{GITHUB_BASE_URL}/tree/#{file_content}"
      rescue Errno::ENOENT
        GITHUB_BASE_URL
      end

      def file_content
        File.read(VERSION_FILE).squish
      end

      def release_date
        File.ctime(VERSION_FILE).to_date.iso8601
      end

      def git_hash?
        file_content&.size == 40
      end
    end
  end
end
