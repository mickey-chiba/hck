class LEDmodule
{
private:
    int _pin;
    int _bri;

public:
    LEDmodule(int pin) : _pin(pin), _bri(0) {}

    void setBrightness(int bri)
    {
        _bri = bri;
        analogWrite(_pin, _bri);
    }
};

int tempo = 120;
LEDmodule led1(3);

void setup()
{
    Serial.begin(9600);
}

void loop()
{
    if (Serial.available() > 0)
    {
        tempo = Serial.parseInt();
    }
    if (tempo <= 30)
    {
        led1.setBrightness(0);
        delay(500);
    }
    else if (30 < tempo <= 45)
    {
        led1.setBrightness(51);
        delay(500);
    }
    else if (45 < tempo <= 60)
    {
        led1.setBrightness(102);
        delay(500);
    }
    else if (60 < tempo <= 75)
    {
        led1.setBrightness(153);
        delay(500);
    }
    else if (75 < tempo <= 90)
    {
        led1.setBrightness(204);
        delay(500);
    }
    else if (90 < tempo <= 120)
    {
        led1.setBrightness(255);
        delay(500);
    }
}