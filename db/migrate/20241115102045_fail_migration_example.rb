class FailMigrationExample < ActiveRecord::Migration[6.1]
  def up
    # Ajouter une colonne 'example_column' à la table 'users'
    add_column :users, :example_column, :string

    # Provoquer une erreur intentionnelle
    raise "Cette migration est destinée à échouer pour les tests"
  end

  def down
    # Supprimer la colonne en cas de rollback
    remove_column :users, :example_column, if_exists: true
  end
end

