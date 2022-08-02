class AddNameToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :name, :string
  end
end
