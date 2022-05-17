class ChangeFeesIdType < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :uuid, :uuid, default: 'gen_random_uuid()', null: false

    change_table :fees do |t|
      t.remove :id
      t.rename :uuid, :id
    end

    execute 'ALTER TABLE fees ADD PRIMARY KEY (id);'
  end
end
