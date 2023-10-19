#include "WiFi.h"
#include "ESPAsyncWebServer.h"
#include "SPI.h"
#include "RTClib.h"
#include "SD.h"
#include <LiquidCrystal_I2C.h>
#include <DHT.h>

#define SENSOR 2

//Display
LiquidCrystal_I2C lcd(0x27, 16, 2);

//Credenciales de WiFi
const char* ssid = "wifi-ubb";
const char* password = "soporte-dci";

//pin sensores
const int pin = 2, sensorPin = 14, sensorPinPir = 16, pinButton= 17;
DHT dht(pin, DHT11);

//Reloj
RTC_DS1307 rtc;
DateTime tiempo;
DateTime lastValidDate;

//Registros de conteo
int act = 0, vis = 0, encendido = 0,LR=LOW;
float hum = 0, temp = 0, flu = 0;
long currentMillis = 0;
long previousMillis = 0;
unsigned long timerLog = 0, timerVis = 0;
byte pulse1Sec = 0;

//Constantes
int interval = 1000;
float calibrationFactor = 4.5;
volatile byte pulseCount;

//archivos
File myFile;

//Funciones
void WriteFile(const char * path, const char * message) {
  myFile = SD.open(path, FILE_WRITE);
  if (myFile) {
    Serial.printf("Writing to %s ", path);
    myFile.println(message);
    myFile.close();
    Serial.println("completed.");
  }
  else {
    Serial.println("error opening file ");
    Serial.println(path);
  }
}

//Agregar datos a un archivo de la SD
void appendFile(const char * path, String message) {
  File file = SD.open(path, FILE_APPEND);
  if (!file) {
    Serial.println("Failed to open file for appending");
    return;
  }
  if (!file.print(message)) {
    Serial.println("Append failed");
  }
  file.close();
}

//registra los datos con el formato "Fecha hora T° Humedad Flujo Activaciones Visitas"
void registrarEnMemoria() {
  String fyh = String (tiempo.timestamp(DateTime::TIMESTAMP_DATE)+" "+tiempo.timestamp(DateTime::TIMESTAMP_TIME));
  String temperatura = String(temp);
  String humedad = String(hum);
  String flujo = String(flu);
  String activaciones = String(act);
  String visitas = String(vis);
  appendFile("/registro.txt", fyh);
  appendFile("/registro.txt", " " + temperatura + " °C ");
  appendFile("/registro.txt", humedad + " % ");
  appendFile("/registro.txt", flujo + " l/m ");
  appendFile("/registro.txt", activaciones + " ");
  appendFile("/registro.txt", visitas + " ");
  appendFile("/registro.txt", "\n");
  Serial.println("datos registrados");
}

void flujo() {
  float flowRate;
  currentMillis = millis();
  if (currentMillis - previousMillis > interval) {

    pulse1Sec = pulseCount;
    pulseCount = 0;

    flowRate = ((1000.0 / (millis() - previousMillis)) * pulse1Sec) / calibrationFactor;
    previousMillis = millis();
    flu = flowRate;
  }
}

void IRAM_ATTR pulseCounter() {
  pulseCount++;
}

// Create AsyncWebServer object on port 80
AsyncWebServer server(80);

String processor(const String& var) {
  
  if (var == "TEMP") {
    return String(temp);
  }
  if (var == "HUM") {
    return String(hum);
  }
  if (var == "VIS") {
    return String(vis);
  }
  if (var == "ACT") {
    return String(act);
  }
  if (var == "FLU") {
    return String(flu);
  }
  return String();
}

void setup() {

  lcd.begin();//lcd.init(); dependiendo de la libreria
  lcd.backlight();
  Serial.begin(115200);
  dht.begin();
  // Connectarse a Wi-Fi
  WiFi.begin(ssid, password);
  Serial.print("Conectando");
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.print(".");
  }
  Serial.println();
  Serial.println(WiFi.localIP());
  //iniciando reloj
  rtc.begin();
  if (! rtc.begin()) {
    Serial.println("Couldn't find RTC");
    Serial.flush();
  }
  if (!rtc.isrunning()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  } else {
    lastValidDate = rtc.now();
  }
  //iniciando SD
  Serial.println("Initializing SD card...");
  if (!SD.begin(5)) {
    Serial.println("initialization failed!");
    //return;
  } else {
    Serial.println("initialization done.");
  }

  // directorio raiz / web page
  server.on("/", HTTP_GET, [](AsyncWebServerRequest * request) {
    request->send(SD, "/index.html", String(), false, processor);
  });

  // ruta para cargar style.css file
  server.on("/style.css", HTTP_GET, [](AsyncWebServerRequest * request) {
    request->send(SD, "/style.css", "text/css");
  });

  //ruta para actualizar la pagina
  server.on("/update", HTTP_GET, [](AsyncWebServerRequest * request) {
    hum = dht.readHumidity();
    temp = dht.readTemperature();
    flujo();
    request->send(SD, "/index.html", String(), false, processor);
  });

  // Start server
  server.begin();
  attachInterrupt(digitalPinToInterrupt(sensorPin), pulseCounter, FALLING);
  // iniciar PIR
  pinMode(sensorPinPir, INPUT);
}

void loop() {

  //muestreo de datos
  hum = dht.readHumidity();
  temp = dht.readTemperature();
  flujo();
  String temper = String(temp);
  String humed = String(hum);
  String flux = String(flu);
  
  //mostrar ip por display los primeros 10 seg
  if (millis() < 10000) {
    lcd.setCursor(0, 0);
    lcd.print(ssid);
    lcd.setCursor(0, 1);
    lcd.print(WiFi.localIP());
    delay(15000);
    lcd.clear();
  }

  //registro
  tiempo = rtc.now();
  unsigned long conteo = millis();
  
  //registro de informacion cada 15 minutos, cambiar la constante de los parentesis para ajustar el intervalo
  if (conteo - timerLog >=900000) {
    timerLog = millis();
    registrarEnMemoria();
  }

  //registro de visitas
  int motionState = digitalRead(sensorPinPir);
  if (motionState == HIGH && conteo - timerVis >= 60000) {
    Serial.print("¡Movimiento detectado!");
    Serial.print("\n");
    motionState = LOW;
    vis++;
    timerVis = millis();
    registrarEnMemoria();
  }

  //lectura de del boton de la bomba
  int motionState2 = digitalRead(pinButton);
  if (motionState2 == HIGH && LR==LOW) {
    act++;
  }
  LR=motionState2;

  //actualizando los datos de la maqueta en pantalla
  lcd.setCursor(0, 0);
  lcd.print(temper + "C");
  lcd.setCursor(0, 1);
  lcd.print(humed + "%");
  lcd.setCursor(7, 0);
  lcd.print(flux + " L/m ");
}