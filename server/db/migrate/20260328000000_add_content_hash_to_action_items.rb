class AddContentHashToActionItems < ActiveRecord::Migration[8.0]
  def change
    add_column :action_items, :content_hash, :string

    # Partial unique index scoped to unhandled rows only.
    # Once an action is marked handled, the same content can be re-created
    # on the next mission run without violating uniqueness.
    add_index :action_items, [ :workspace_id, :content_hash ],
              name: "idx_action_items_workspace_content_hash_unhandled",
              unique: true,
              where: "is_handled = false"
  end
end
