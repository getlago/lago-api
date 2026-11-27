# frozen_string_literal: true

class CurrentContext < ActiveSupport::CurrentAttributes
  attribute :membership, :source, :email, :api_key_id, :device_info

  # The membership as audit trails and tracking read it: "membership/<id>".
  def membership_id
    membership&.delete_prefix("membership/")
  end

  def membership_id=(id)
    self.membership = id && "membership/#{id}"
  end
end
