class ChangeMembershipsIdDatatype < ActiveRecord::Migration[7.0]
  def change
    add_column :memberships, :uuid, :uuid, default: 'gen_random_uuid()', null: false

    change_table :memberships do |t|
      t.remove :id
      t.rename :uuid, :id
    end

    execute 'ALTER TABLE memberships ADD PRIMARY KEY (id);'
  end
end
