# frozen_string_literal: true

class AddNumberToInvoices < ActiveRecord::Migration[7.0]
  def change
    # NOTE: sequential_id scope change we have to reset the column
    remove_index :invoices, :sequential_id
    remove_column :invoices, :sequential_id, :integer

    add_column :invoices, :number, :string, null: false, index: true, default: ""
    add_column :invoices, :sequential_id, :integer, index: true

    LagoApi::Application.load_tasks
    Rake::Task["invoices:generate_number"].invoke
  end
end
