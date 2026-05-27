# frozen_string_literal: true

module PreloaderCache
  extend ActiveSupport::Concern

  def preloader_cache
    @preloader_cache ||= {}
  end
end
