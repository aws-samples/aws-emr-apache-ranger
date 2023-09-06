#!/bin/bash

set -x

if grep isMaster /mnt/var/lib/info/instance.json | grep false;
then
  echo "This is not master node, do nothing, exiting"
  exit 0
fi
while [ ! -f /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py ]
do
  sleep 1
done

sudo sed -i -e ':a' -e 'N' -e '$!ba' -e 's+# limitations under the License.\n\n+# limitations under the License.\n\nimport socket\ntry:\n  from sqlalchemy.engine.url import make_url\nexcept:\n  class SQLAlchemy_URL:\n    pass\n  def make_url(url):\n    db_url = SQLAlchemy_URL()\n    db_url.drivername = url.split(":")\[0\]\n    return db_url\n\n+' /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py
sudo sed -i -e ':a' -e 'N' -e '$!ba' -e "s+API_CACHE = {}\n\n+API_CACHE = {}\n\n# List of database engine types with no auth modal when on the cluster's primary node\nENGINES_WITH_NO_AUTH_MODAL = \['presto', 'trino'\]\n+" /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py
sudo sed -i -e ':a' -e 'N' -e '$!ba' -e "s+      if 'password' in properties:\n        user = properties.get('user') or self.options.get('user')\n        props\['properties'\] = {'user': user}\n        self.db = API_CACHE\[self.cache_key\] = Jdbc(self.options\['driver'\], self.options\['url'\], user, properties.pop('password'))\n+      if True:\n        # Use the currently authenticated user's username by default to prevent unauthenticated impersonation\n        # This applies to Presto/Trino databases on the cluster's primary node\n        user = self.user.username\n        password = ''\n        db_url = make_url(self.options\['url'\]\[5:\])\n        url_host = str(db_url).split(':')\[1\]\n        current_host = socket.gethostname()\n        # If a password is already provided (in hue.ini), use those credentials\n        if 'password' in properties:\n          user = properties.get('user') or self.options.get('user')\n          password = properties.pop('password')\n        # Otherwise, prompt auth modal if the database is not a Presto/Trino database or if it is not located on this node\n        elif current_host not in url_host or db_url.drivername not in ENGINES_WITH_NO_AUTH_MODAL:\n          raise AuthenticationRequired()\n        props\['properties'\] = {'user': user}\n        self.db = API_CACHE\[self.cache_key\] = Jdbc(self.options\['driver'\], self.options\['url'\], user, password)\n+" /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py
sudo sed -i -e ':a' -e 'N' -e '$!ba' -e 's+if self.db is None:\n      raise AuthenticationRequired()\n+if self.db is None:\n      self.create_session()\n+g' /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py
sudo sed -i "s+(throw_exception='password' not in properties)+()+g" /usr/lib/hue/desktop/libs/notebook/src/notebook/connectors/jdbc.py

sudo systemctl stop hue
sudo systemctl start hue