class AddMembershipIdAndOrganizationIdToDataExports < ActiveRecord::Migration[7.1]
  def change
    add_reference :data_exports, :membership, null: false, foreign_key: true, type: :uuid
    add_reference :data_exports, :organization, null: false, foreign_key: true, type: :uuid
  end
end
