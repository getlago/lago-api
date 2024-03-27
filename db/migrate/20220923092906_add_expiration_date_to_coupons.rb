# frozen_string_literal: true

class AddExpirationDateToCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :expiration_date, :date

    LagoApi::Application.load_tasks
    Rake::Task["coupons:fill_expiration_date"].invoke

    remove_column :coupons, :expiration_duration, :integer
  end
end
