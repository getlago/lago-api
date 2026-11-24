# frozen_string_literal: true

class AddDraftToContractStatus < ActiveRecord::Migration[8.0]
  def change
    add_enum_value :contract_status, "draft", before: "pending", if_not_exists: true
  end
end
