#include <Arduino.h>

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
int count = 0;
LEDmodule led1(3);

void setup()
{
    Serial.begin(9600);
}

void loop()
{
    u_int64_t millis_buf = 0;

    while ((millis() - millis_buf) < 1000)
    {
        ;
    }

    millis_buf = millis();
    Serial.println(millis_buf);

    count++;
    Serial.println(count);
    if (Serial.available() > 0)
    {
        tempo = Serial.parseInt();
    }
    if (tempo <= 30)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(0);
        }
    }
    else if (30 < tempo && tempo <= 45)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(51);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (45 < tempo && tempo <= 60)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(102);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (60 < tempo && tempo <= 75)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(153);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (75 < tempo && tempo <= 90)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(204);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
    else if (90 < tempo && tempo <= 120)
    {
        if ((count % 50) == 0)
        {
            led1.setBrightness(255);
            if ((count % 100) == 0)
            {
                led1.setBrightness(0);
            }
        }
    }
}