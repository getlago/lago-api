# frozen_string_literal: true

class AddPaginationMaxPageSizeToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :pagination_max_page_size, :integer, if_not_exists: true
  end
end
