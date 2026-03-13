# frozen_string_literal: true

class AddSkipAutomaticPdfGenerationToBillingEntities < ActiveRecord::Migration[8.0]
  def change
    add_column :billing_entities, :skip_automatic_pdf_generation, :string, array: true, default: [], null: false
  end
end
