# frozen_string_literal: true

namespace :lago do
  desc 'Print the current version of Lago'
  task version: :environment do
    puts({number: LAGO_VERSION.number, github_url: LAGO_VERSION.github_url}.to_json)
  end
end
