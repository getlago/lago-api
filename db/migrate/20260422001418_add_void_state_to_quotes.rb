# frozen_string_literal: true

class AddVoidStateToQuotes < ActiveRecord::Migration[8.0]
  def change
    create_enum :quote_void_reason, %w[manual superseded cascade_of_expired cascade_of_voided]

    add_column :quotes, :voided_at, :timestamptz, if_not_exists: true
    add_column :quotes, :void_reason, :enum, enum_type: :quote_void_reason, if_not_exists: true
  end
end
