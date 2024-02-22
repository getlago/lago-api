# frozen_string_literal: true

module Auth
  class GoogleController < ApplicationController
    def index
      redirect(Auth::GoogleService.new.authorize)
    end

    def callback
      # TODO: Implement
    end
  end
end
