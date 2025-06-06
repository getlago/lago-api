# frozen_string_literal: true

class CurrentContext < ActiveSupport::CurrentAttributes
  attribute :membership, :source, :email, :api_key_id
end
