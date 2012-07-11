before_fork do |server, number|
  puts "foo"
end

after_fork do |server, number|
  puts "boo"
end