class EnableBtreeGist < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist"
  end
end
