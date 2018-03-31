module TheSync
  module Table

    def instance_table
      # 'source.table_name'
      if same_server?
        @dest_table_name = @adapter.client.query_options[:database].to_s + '.' + @dest_table.to_s
      else
        @dest_table_name = options[:dest].to_s + '_' + @table_name
      end
    end

    def same_server?
      connection.raw_connection.query_options[:connect_flags] == @adapter.client.query_options[:connect_flags]
    end

    def dest_columns
      @adapter.columns(@dest_table)
    end

    def dest_indexes
      results = @adapter.indexes(@dest_table)
      results = results.map { |result| { result['INDEX_NAME'] => result['COLUMN_NAME'] } }
      results.to_combined_hash  # rails_com core ext
      results.delete('PRIMARY')
      results
    end

    def dest_primary_key
      results = @adapter.primary_key(@dest_table)
      Hash(results[0])['COLUMN_NAME']
    end

    def dest_sql_table(only: [], except: [], pure: true)
      if only.size > 0
        _columns = dest_columns.select { |column| only.include?(column['COLUMN_NAME']) }
      else
        _columns = dest_columns.reject { |column| except.include?(column['COLUMN_NAME']) }
      end

      if pure
        sql = ""
      else
        sql = "CREATE TABLE `#{@dest_table}` (\n"
      end

      _columns.each do |column|
        sql << "  `#{column['COLUMN_NAME']}` #{column['COLUMN_TYPE']}"
        sql << " COLLATE #{column['COLLATION_NAME']}" if column['COLLATION_NAME'].present?
        sql << " NOT NULL" if column['IS_NULLABLE'] == 'NO'
        if column['COLUMN_DEFAULT']
          sql << " DEFAULT '#{column['COLUMN_DEFAULT']}',\n"
        elsif column['COLUMN_DEFAULT'].nil? && column['IS_NULLABLE'] == 'YES'
          sql << " DEFAULT NULL,\n"
        else
          sql << ",\n"
        end
      end

      sql << "  PRIMARY KEY (`#{dest_primary_key}`)"

      _indexes = dest_indexes.reject { |_, value| (Array(value) & _columns.map { |col| col['COLUMN_NAME'] }).blank? }

      if _indexes.present?
        sql << ",\n"
      else
        sql << "\n"
      end
      _indexes.each do |index, columns|
        sql << "  KEY `#{index}` ("
        sql << Array(columns).map { |col| "`#{col}`" }.join(',')
        sql << "),\n"
      end

      sql.chomp!(",\n")

      if pure
        sql
      else
        sql << ")"
      end
    end

    def migrate_sync
      reset_temp_table
    end

    def reset_temp_table
      drop_temp_table
      create_temp_table
    end

    def create_temp_table
      sql = "CREATE TABLE #{@dest_table_name} (\n"
      sql << dest_sql_table(only: @dest_columns)
      sql << ")"
      sql << "ENGINE=FEDERATED\n"
      sql << "CONNECTION='#{adapter.connection}/#{@dest_table}';"

      @connection.execute(sql)
    end

    def drop_temp_table
      sql = "DROP TABLE IF EXISTS `#{@dest_table_name}`"

      @connection.execute(sql)
    end

    def source_select
      query = table.project columns.map { |column| table[column] }
      query = query.where table[primary_key].in(ids)

      @connection.execute(query.to_sql).each
    end

  end
end
