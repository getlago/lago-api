# frozen_string_literal: true

class FillCustomerIdOnInvoices < ActiveRecord::Migration[7.0]
  def change
    LagoApi::Application.load_tasks
    Rake::Task["invoices:fill_customer"].invoke
  end
end
