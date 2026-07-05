# REST and SOAP security examples

Az `app1` - `app6` alkalmazasok `application.yaml` fajljainak vegen van egy `external-services` pelda szekcio. Ezek jelenleg dokumentacios es konfiguracios mintak, a pipeline kod meg nem hivja oket automatikusan.

A cel az, hogy ha kesobb REST vagy SOAP kulso rendszert kell hivni, akkor ne Java forrasba legyenek egetve az URL-ek, jelszavak, timeoutok, JKS fajlok vagy security beallitasok.

## Hol vannak a peldak?

Apponkent:

```text
app1\src\main\resources\application.yaml
app2\src\main\resources\application.yaml
app3\src\main\resources\application.yaml
app4\src\main\resources\application.yaml
app5\src\main\resources\application.yaml
app6\src\main\resources\application.yaml
```

JKS helye apponkent:

```text
appN\src\main\resources\security
```

Pelda:

```text
app1\src\main\resources\security\rest-client-truststore.jks
app1\src\main\resources\security\rest-client-keystore.jks
app1\src\main\resources\security\soap-client-truststore.jks
app1\src\main\resources\security\soap-client-keystore.jks
```

Ezek a JAR reszei lesznek, mert a `src/main/resources` ala kerulnek.

Ha uj JKS fajlt teszel ide, utana ujra kell buildelni az app JAR-t es az app image-et, majd uj offline bundle-t kell kesziteni. Az `application.yaml` runtime mountolva van, de a `classpath:security/...` fajlok a JAR-bol jonnek.

## REST pelda

Az `external-services.rest-order-api` blokk REST klienshez ad mintat:

```yaml
external-services:
  rest-order-api:
    enabled: false
    base-url: '${REST_ORDER_API_BASE_URL:https://partner.example.local/api}'
    connect-timeout: 5s
    read-timeout: 30s
    auth:
      mode: mtls
    tls:
      enabled: true
      trust-store: classpath:security/rest-client-truststore.jks
      key-store: classpath:security/rest-client-keystore.jks
```

Tamogatott mintak a konfiguracioban:

```text
none
basic
bearer
mtls
oauth2-client-credentials
```

Pelda REST hivasok a YAML-ban:

```yaml
example-calls:
  create-order:
    method: POST
    path: /orders
    content-type: application/json
  get-order:
    method: GET
    path: /orders/{orderId}
```

## SOAP pelda

Az `external-services.soap-partner-service` blokk SOAP klienshez ad mintat:

```yaml
external-services:
  soap-partner-service:
    enabled: false
    wsdl-url: '${SOAP_PARTNER_WSDL_URL:https://partner.example.local/ws/orders?wsdl}'
    endpoint-url: '${SOAP_PARTNER_ENDPOINT_URL:https://partner.example.local/ws/orders}'
    soap-version: SOAP_12
    soap-action: 'urn:SubmitOrder'
    auth:
      mode: mtls
    tls:
      enabled: true
      trust-store: classpath:security/soap-client-truststore.jks
      key-store: classpath:security/soap-client-keystore.jks
```

Tamogatott mintak a konfiguracioban:

```text
none
basic
mtls
ws-security-username-token
```

Pelda SOAP muveletek:

```yaml
example-calls:
  submit-order:
    operation: SubmitOrder
    request-root: SubmitOrderRequest
    response-root: SubmitOrderResponse
  get-order-status:
    operation: GetOrderStatus
    request-root: GetOrderStatusRequest
    response-root: GetOrderStatusResponse
```

## JKS hasznalat

Truststore:

```text
Szerver tanusitvanyanak vagy CA tanusitvanyanak ellenorzese.
```

Keystore:

```text
Kliens tanusitvany mTLS-hez.
```

Javasolt fajlnevek:

```text
rest-client-truststore.jks
rest-client-keystore.jks
soap-client-truststore.jks
soap-client-keystore.jks
```

Classpath hivatkozas:

```yaml
trust-store: classpath:security/rest-client-truststore.jks
key-store: classpath:security/rest-client-keystore.jks
```

## Jelszavak

Pelda:

```yaml
trust-store-password: '${REST_ORDER_API_TRUSTSTORE_PASSWORD:changeit}'
```

Ez azt jelenti:

- ha van `REST_ORDER_API_TRUSTSTORE_PASSWORD` environment variable, akkor azt hasznalja;
- ha nincs, akkor a pelda `changeit` fallback erteket.

Eles kornyezetben ne maradjon `changeit`.

## Hogyan lesz ebbol kod?

Ha REST klienst keszitesz Spring Bootban, hozz letre egy configuration properties osztalyt, peldaul:

```text
ExternalServicesProperties
```

Es kossed be:

```java
@ConfigurationProperties(prefix = "external-services")
```

SOAP kliensnel ugyanez az elv: a WSDL URL, endpoint URL, SOAPAction, timeout, JKS es auth mezok ne kodban legyenek, hanem az `application.yaml`-bol jojjenek.

## Fontos

- Ezek a mintak nem valtoztatjak meg a mostani appok futasat.
- Az `enabled: false` miatt dokumentacios jelleguek.
- Ha egy kulso hivast tenylegesen bekotsz, az adott blokkot allitsd `enabled: true`-ra.
- A JKS fajlokat az adott app `src/main/resources/security` konyvtaraba tedd.
- JKS modositas utan futtasd ujra az app buildet es az offline exportot, mert a classpath-os JKS fajloknak a JAR-ba is be kell kerulniuk.
