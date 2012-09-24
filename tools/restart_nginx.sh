#!/bin/bash

find /var/log/httpd/ips/ -type f -mmin +30 -exec rm {} -f \;

mv /etc/nginx/conf.d/wiki.conf /etc/nginx/conf.d/wiki.conf.prev

echo 'upstream  wiki_site  {' > /etc/nginx/conf.d/wiki.conf

ls /var/log/httpd/ips/ | while IFS= read IP; do
	ping -c 1 -W 1 $IP > /dev/null 2>&1
	if [[ $? == 0 ]]; then
		echo "   server   $IP max_fails=3  fail_timeout=60s;" >> /etc/nginx/conf.d/wiki.conf;
	fi
done 

MEME=$(cat /etc/nginx/conf.d/wiki.conf | wc -l)
if [[ $MEME == 1 ]];then
    echo '   server   10.0.0.99:8000;' >> /etc/nginx/conf.d/wiki.conf;
fi

echo '   server   10.0.0.99:8000 backup;
}

upstream  local_site  {
   server   10.0.0.99:8000;
}

server {
   listen       80;
   server_name wiki;
   location / {
      proxy_pass  http://wiki_site/;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
   }
   location /awstats/ {
      proxy_pass  http://local_site/awstats/;
   }
   location /munin/ {
      proxy_pass  http://local_site/munin/;
   }
}
' >> /etc/nginx/conf.d/wiki.conf

DIFF=$(diff /etc/nginx/conf.d/wiki.conf /etc/nginx/conf.d/wiki.conf.prev)

if [[ $DIFF != "" ]]; then 
#	echo "restart nginx"
#	kill -HUP $(ps -ef | grep nginx | grep master | gawk '{print $2}')
	kill -9 $(ps -ef | grep nginx | grep -v grep | grep -v restart_nginx | gawk '{print $2}')
	sleep 1
	/etc/init.d/nginx restart
fi
