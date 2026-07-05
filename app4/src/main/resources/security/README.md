# Security resources

Ide kerulhetnek az app JAR-ba csomagolt JKS fajlok.

Pelda fajlnevek:

- sqlserver-truststore.jks
- kafka.client.truststore.jks
- kafka.client.keystore.jks
- external-client-truststore.jks
- external-client-keystore.jks

YAML hivatkozas pelda:

classpath:security/kafka.client.truststore.jks

JKS fajl csereje utan uj Maven build kell, mert ezek a fajlok a JAR reszei.