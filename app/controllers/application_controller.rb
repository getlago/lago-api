# frozen_string_literal: true

class ApplicationController < ActionController::API
  def health
    result = Utils::VersionService.new.version

    render(
      json: {
        version: result.version.number,
        github_url: result.version.github_url,
        message: 'Success',
      },
      status: :ok,
    )
  end
end
