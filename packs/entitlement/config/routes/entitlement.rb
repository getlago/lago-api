# frozen_string_literal: true

scope :entitlement do
  get "/policy", to: "policy#index"
end
