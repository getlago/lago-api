# frozen_string_literal: true

namespace :lago do
  desc 'Print the current version of Lago'
  task version: :environment do
    version = Utils::VersionService.call.version

    puts({number: version.number, github_url: version.github_url}.to_json)
  end
end
