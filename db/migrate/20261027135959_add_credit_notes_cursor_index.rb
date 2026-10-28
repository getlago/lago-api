# frozen_string_literal: true

class AddCreditNotesCursorIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would keep: drop it so a retry builds the index again.
    if index_exists?(:credit_notes, nil, name: :index_credit_notes_by_cursor, valid: false)
      remove_index :credit_notes, name: :index_credit_notes_by_cursor, algorithm: :concurrently
    end

    add_index :credit_notes,
      [:organization_id, :created_at, :id],
      order: {created_at: :desc, id: :desc},
      where: "status = 1",
      name: :index_credit_notes_by_cursor,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :credit_notes, name: :index_credit_notes_by_cursor, algorithm: :concurrently, if_exists: true
  end
end
