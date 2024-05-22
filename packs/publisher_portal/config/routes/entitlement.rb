# frozen_string_literal: true

require 'entitlement/authorization_controller'

namespace :api do
  namespace :v1 do
    namespace :entitlement do
      get '/authorization', to: 'authorization#index'
    end
  end
end
