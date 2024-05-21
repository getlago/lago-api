# frozen_string_literal: true

scope :entitlement do
  get '/authorization', to: 'authorization#index'
end
