# Extension to make it easy to read and write data to a file.
class ActiveRecord::Base

  class << self

    # Writes content of this table to db/table_name.yml, or the specified file.
    #
    # Writes all content by default, but can be limited.
    def dump_to_file(path=nil, opts=[])
      path ||= "db/#{table_name}.json"
      records = case opts
        when Array
          self.find(opts)
        when Hash
          self.find(:all, opts)
      end.to_json
      write_file(File.expand_path(path, RAILS_ROOT), records)
    end
  
    # Delete existing data in database and load fresh from file in db/table_name.yml
    def load_from_file(path=nil)
      path ||= "db/#{table_name}.json"

      self.destroy_all

      if connection.respond_to?(:reset_pk_sequence!)
       connection.reset_pk_sequence!(table_name)
      end

      records = JSON::parse( File.open( File.expand_path(path, RAILS_ROOT), 'rb' ) { |f| f.read })
      records.each do |record|
        attributes = record[table_name.singularize.to_s]
        record_copy = self.new(attributes)
        record_copy.id = attributes['id']

        # For Single Table Inheritance
        klass_col = self.inheritance_column
        if attributes[klass_col]
           record_copy.type = attributes[klass_col]
        end
      
        record_copy.save
      end
 
      if connection.respond_to?(:reset_pk_sequence!)
       connection.reset_pk_sequence!(table_name)
      end
    end

    # Write a file that can be loaded with +fixture :some_table+ in tests.
    # Uses existing data in the database.
    #
    # Will be written to +test/fixtures/table_name.yml+. Can be restricted to some number of rows.
    def to_fixture(limit=nil)
      opts = {}
      opts[:limit] = limit if limit

      write_file(File.expand_path("test/fixtures/#{table_name}.json", RAILS_ROOT), 
          self.find(:all, opts).inject({}) { |hsh, record| 
              hsh.merge("#{table_name.singularize}_#{'%05i' % record.id}" => record.attributes) 
            }.to_yaml(:SortKeys => true))
      habtm_to_fixture
    end

    # Write the habtm association table
    def habtm_to_fixture
      joins = self.reflect_on_all_associations.select { |j|
        j.macro == :has_and_belongs_to_many
      }
      joins.each do |join|
        hsh = {}
        connection.select_all("SELECT * FROM #{join.options[:join_table]}").each_with_index { |record, i|
          hsh["join_#{'%05i' % i}"] = record
        }
        write_file(File.expand_path("test/fixtures/#{join.options[:join_table]}.json", RAILS_ROOT), hsh.to_yaml(:SortKeys => true))
      end
    end
    
    # Generates a basic fixture file in test/fixtures that lists the table's field names.
    #
    # You can use it as a starting point for your own fixtures.
    #
    #  record_1:
    #    name:
    #    rating:
    #  record_2:
    #    name:
    #    rating:
    #
    # TODO Automatically add :id field if there is one.
    def to_skeleton
      record = { 
          "record_1" => self.new.attributes,
          "record_2" => self.new.attributes
         }
      write_file(File.expand_path("test/fixtures/#{table_name}.json", RAILS_ROOT),
        record.to_yaml)
    end

    def write_file(path, content) # :nodoc:
      f = File.new(path, "w+")
      f.puts content
      f.close
    end

  end

end
