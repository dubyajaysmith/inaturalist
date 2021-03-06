user_id = ARGV[0]
table_names = []
resurrection_cmds = []
dbname = ActiveRecord::Base.connection.current_database

puts
puts <<-EOT
This script assumes you're currently connected to a database that has the data
you want to export, so if it bails b/c it can't find your user, that's
probably why.
EOT
puts

system "rm resurrect_#{user_id}*"

puts "Exporting from users..."
fname = "resurrect_#{user_id}-users.csv"
cmd = "psql #{dbname} -c \"COPY (SELECT * FROM users WHERE id = #{user_id}) TO STDOUT WITH CSV\" > #{fname}"
puts "\t#{cmd}"
system cmd
resurrection_cmds << "psql #{dbname} -c \"\\copy users FROM '#{fname}' WITH CSV\""

# puts "Exporting from photos (except LocalPhotos, which are gone)..."
# fname = "resurrect_#{user_id}-photos.csv"
# cmd = "psql #{dbname} -c \"COPY (SELECT * FROM photos WHERE user_id = #{user_id} AND type != 'LocalPhoto') TO STDOUT WITH CSV\" > #{fname}"
# puts "\t#{cmd}"
# system cmd
# resurrection_cmds << "psql #{dbname} -c \"\\copy photos FROM '#{fname}' WITH CSV\""

update_statements = []

has_many_reflections = User.reflections.select{|k,v| v.macro == :has_many}
has_many_reflections.each do |k, reflection|
  # Avoid those pesky :through relats
  next unless reflection.klass.column_names.include?(reflection.foreign_key)
  next unless reflection.options[:dependent] == :destroy
  next if %w(observations observation_field_values project_observations identifications).include?( k.to_s )
  puts "Exporting #{k}..."
  fname = "resurrect_#{user_id}-#{reflection.table_name}.csv"
  unless table_names.include?(reflection.table_name)
    system "test #{fname} || rm #{fname}"
  end
  cmd = "psql #{dbname} -c \"COPY (SELECT * FROM #{reflection.table_name} WHERE #{reflection.foreign_key} = #{user_id}) TO STDOUT WITH CSV\" >> #{fname}"
  system cmd
  puts "\t#{cmd}"
  resurrection_cmds << "psql #{dbname} -c \"\\copy #{reflection.table_name} FROM '#{fname}' WITH CSV\""
end

puts "Exporting from listed_taxa..."
fname = "resurrect_#{user_id}-listed_taxa.csv"
sql = <<-SQL
SELECT listed_taxa.* 
FROM 
  listed_taxa 
    JOIN lists ON lists.id = listed_taxa.list_id
WHERE
  lists.user_id = #{user_id}
SQL
cmd = "psql #{dbname} -c \"COPY (#{sql.gsub("\n", ' ')}) TO STDOUT WITH CSV\" > #{fname}"
puts "\t#{cmd}"
system cmd
resurrection_cmds << "psql #{dbname} -c \"\\copy listed_taxa FROM '#{fname}' WITH CSV\""

puts "Exporting from guide_taxa..."
fname = "resurrect_#{user_id}-guide_taxa.csv"
sql = <<-SQL
SELECT guide_taxa.* 
FROM 
  guide_taxa 
    JOIN guides ON guides.id = guide_taxa.guide_id
WHERE
  guides.user_id = #{user_id}
SQL
cmd = "psql #{dbname} -c \"COPY (#{sql.gsub(/\s+/, ' ')}) TO STDOUT WITH CSV\" > #{fname}"
puts "\t#{cmd}"
system cmd
resurrection_cmds << "psql #{dbname} -c \"\\copy guide_taxa FROM '#{fname}' WITH CSV\""

%w(guide_photos guide_ranges guide_sections).each do |table_name|
  puts "Exporting from #{table_name}..."
  fname = "resurrect_#{user_id}-#{table_name}.csv"
  sql = <<-SQL
  SELECT #{table_name}.* 
  FROM 
    #{table_name} 
      JOIN guide_taxa ON guide_taxa.id = #{table_name}.guide_taxon_id
      JOIN guides ON guides.id = guide_taxa.guide_id
  WHERE
    guides.user_id = #{user_id}
  SQL
  cmd = "psql #{dbname} -c \"COPY (#{sql.gsub(/\s+/, ' ')}) TO STDOUT WITH CSV\" > #{fname}"
  puts "\t#{cmd}"
  system cmd
  resurrection_cmds << "psql #{dbname} -c \"\\copy #{table_name} FROM '#{fname}' WITH CSV\""
end

# TODO restore subscriptions to user

cmd = "tar cvzf resurrect_#{user_id}.tgz resurrect_#{user_id}-*"
puts "Zipping it all up..."
puts "\t#{cmd}"
system cmd

cmd = "rm resurrect_#{user_id}-*"
puts "Cleaning up..."
puts "\t#{cmd}"
system cmd

puts
puts "Run these commands (or something like them, depending on your setup):"
puts
puts <<-EOT
scp resurrect_#{user_id}.tgz inaturalist@taricha:deployment/production/current/
ssh -t inaturalist@taricha "cd deployment/production/current ; bash"
tar xzvf resurrect_#{user_id}.tgz
#{resurrection_cmds.uniq.join("\n")}
EOT
puts
puts "This script does not resurrect observations or associated data. Please use tools/resurrect_observations.rb for that."
puts
