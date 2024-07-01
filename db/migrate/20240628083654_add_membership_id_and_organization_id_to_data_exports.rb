class AddMembershipIdAndOrganizationIdToDataExports < ActiveRecord::Migration[7.1]
  def change
    add_reference :data_exports, :membership, foreign_key: true, type: :uuid
    add_reference :data_exports, :organization, foreign_key: true, type: :uuid
  end
end
