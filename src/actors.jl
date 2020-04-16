export lead, follow, join

function follow(cluster::Cluster, conn::Connection)
end

function lead(cluster::Cluster, clients::Connection, followers::Connection)
  
end

function run(cluster, conn::Connection)
  while true
    follow(cluster, conn)
    lead(cluster, conn)
  end
end