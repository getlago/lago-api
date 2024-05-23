# frozen_string_literal: true

require 'v1/entitlement/authorization_controller'

namespace :v1 do
  namespace :entitlement do
    get '/authorization', to: 'authorization#index'
  end
end
