# frozen_string_literal: true

class AddCategoryToIntegrations < ActiveRecord::Migration[7.1]
  module Integrations
    class BaseIntegration < ApplicationRecord
      self.table_name = 'integrations'
      INTEGRATION_CATEGORIES = %w[system accounting tax_provider]
      enum category: INTEGRATION_CATEGORIES
    end

    class AnrokIntegration < BaseIntegration
    end

    class NetsuiteIntegration < BaseIntegration
    end

    class XeroIntegration < BaseIntegration
    end

    class OktaIntegration < BaseIntegration
    end
  end

  def up
    add_column :integrations, :category, :integer
    add_index :integrations, :category

    Integrations::AnrokIntegration.update_all(category: 'tax_provider') # rubocop:disable Rails/SkipsModelValidations
    Integrations::NetsuiteIntegration.update_all(category: 'accounting') # rubocop:disable Rails/SkipsModelValidations
    Integrations::XeroIntegration.update_all(category: 'accounting') # rubocop:disable Rails/SkipsModelValidations
    Integrations::OktaIntegration.update_all(category: 'system') # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    remove_index :integrations, :category
    remove_column :integrations, :category
  end
end
