# frozen_string_literal: true

require 'entitlement/authorization_controller'

namespace :entitlement do
  get '/authorization', to: 'authorization#index'
end
