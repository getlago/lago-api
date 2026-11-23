# frozen_string_literal: true

class CreateExportsBillingSegments < ActiveRecord::Migration[8.1]
  def change
    create_view :exports_billing_segments, version: 1
  end
end
