# frozen_string_literal: true

class AddMembershipIdAndOrganizationIdToDataExports < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      add_reference :data_exports, :membership, foreign_key: true, type: :uuid
      add_reference :data_exports, :organization, foreign_key: true, type: :uuid
    end
  end
end
