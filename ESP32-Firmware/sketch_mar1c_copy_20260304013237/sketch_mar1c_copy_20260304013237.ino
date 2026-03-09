#include <Arduino.h>
#include <Arduino_GFX_Library.h>


// =====================================================
// MARK: - Color Defines
// [TAG: COLOR_DEFINES]
// =====================================================
#define BLACK 0x0000
#define WHITE 0xFFFF

static const uint16_t C_BG      = 0x0841;
static const uint16_t C_TOPBAR  = 0x1082;
static const uint16_t C_CARD    = 0x10A2;
static const uint16_t C_BORDER  = 0x2965;
static const uint16_t C_TEXT    = 0xFFFF;
static const uint16_t C_MUTED   = 0xB596;
static const uint16_t C_ACCENT  = 0x4DFF;
static const uint16_t C_GOOD    = 0x07E0;
static const uint16_t C_WARN    = 0xFD20;
static const uint16_t C_BAD     = 0xF800;
static const uint16_t C_TRACK   = 0x2124;


// =====================================================
// MARK: - ESP Pins
// [TAG: ESP_PINS]
// =====================================================
#define TFT_MOSI   6
#define TFT_SCLK   7
#define TFT_CS     14
#define TFT_DC     15
#define TFT_RST    21
#define TFT_BL     22


// =====================================================
// MARK: - Panel Geometry
// [TAG: ESP_PANEL]
// Keep hardware/display setup unchanged.
// =====================================================
static const int LCD_XOFF = 34;
static const int LCD_YOFF = 0;

// Real drawing space after setRotation(3)
static const int SCREEN_WIDTH = 320;
static const int SCREEN_HEIGHT = 172;

// Grid
static const int TOP_BAR_H = 0;
static const int CONTENT_Y = 0;
static const int CONTENT_H = 148; // 0..147
static const int BOTTOM_Y = 148;
static const int BOTTOM_H = 24;   // 148..171
static const int MARGIN_X = 10;
static const int CARD_W = 300;
static const int PROGRESS_H = 6;
static const int TEXT_MAX_PX = 280;


// =====================================================
// MARK: - GFX Objects
// [TAG: ESP_GFX_OBJECTS]
// =====================================================
Arduino_DataBus *bus = new Arduino_HWSPI(
  TFT_DC, TFT_CS,
  TFT_SCLK, TFT_MOSI, /*MISO*/ -1
);

Arduino_GFX *gfx = new Arduino_ST7789(
  bus,
  TFT_RST,
  /*rotation*/ 3,
  /*ips*/ true,
  /*width*/ 240,
  /*height*/ 320,
  /*col_offset*/ LCD_XOFF,
  /*row_offset*/ LCD_YOFF
);


// =====================================================
// MARK: - View Enum
// [TAG: VIEW_ENUM]
// =====================================================
enum ViewMode {
  VIEW_IDLE,
  VIEW_MUSIC,
  VIEW_FOCUS,
  VIEW_TASKS,
  VIEW_HABITS,
  VIEW_COACH,
  VIEW_GAME,
  VIEW_STATS,
  VIEW_SETTINGS
};

ViewMode viewMode = VIEW_IDLE;

enum AIStyleMode {
  AI_STYLE_ORB = 0,
  AI_STYLE_FACE = 1,
  AI_STYLE_STATUS = 2
};


// =====================================================
// MARK: - Data State
// [TAG: ESP_STATE]
// =====================================================
String timeStr = "--:--";
String dateStr = "";

String musicState = "stopped";
String musicArtist = "";
String musicTitle  = "";
long musicPosSec = -1;
long musicDurSec = -1;

String pomoPhase = "focus";
int pomoRemaining = 0;
int pomoTotal = 1;
bool pomoRunning = false;

int tasksOpenCount = 0;
int tasksDueSoonCount = 0;

int habitsDoneToday = 0;
int habitsTotalToday = 0;
int habitsStreak = 0;

String coachStatus = "idle";
String coachHint = "No hint";
AIStyleMode aiStyleMode = AI_STYLE_ORB;

int gameLevel = 1;
int gameXp = 0;
int gameStreak = 0;
int gameSkillFocus = 0;
int gameSkillLearning = 0;
int gameSkillConsistency = 0;
int gameRadar[6] = {0, 0, 0, 0, 0, 0};
bool gameHasGamifyData = false;

int statsTodayMin = 0;
int statsWeekMin = 0;
int statsMonthMin = 0;

int settingsBrightness = 80;
int settingsVolume = 50;
String settingsUsb = "ok";

String selectedHabitId = "";
String selectedHabitTitle = "-";
String selectedHabitSymbol = "checkmark.circle";
String selectedHabitColor = "#24C483";
int selectedHabitStreak = 0;
int selectedHabitDoneToday = 0;

String dbgLastLine = "";
String dbgLastError = "";


// =====================================================
// MARK: - Perf Redraw Policy
// [TAG: PERF_REDRAW_POLICY]
// =====================================================
static const unsigned long FRAME_INTERVAL_MS = 100UL;    // max 10 FPS
static const unsigned long STATUS_INTERVAL_MS = 15000UL;
static const unsigned long RX_TIMEOUT_MS = 8000UL;

static bool fullRedrawPending = true;
static bool contentDirty = true;
static bool topBarDirty = true;

static unsigned long lastFrameMs = 0;
static unsigned long lastStatusMs = 0;
static unsigned long lastRxMs = 0;
static bool linkOk = false;
static unsigned long lastCoachAnimMs = 0;

// [TAG: POMO_PROGRESS_UPDATE]
static unsigned long lastPomoTickMs = 0;

// [TAG: HABIT_DONE_ANIM]
static bool habitDoneAnimActive = false;
static unsigned long habitDoneAnimStartMs = 0;
static unsigned long habitDoneAnimDurationMs = 1000;


// =====================================================
// MARK: - Serial RX Buffer
// [TAG: ESP_SERIAL_READ]
// =====================================================
static const uint16_t RX_LINE_MAX = 360;
static const uint16_t RX_BYTES_PER_POLL = 192;

static char inLine[RX_LINE_MAX];
static uint16_t inLineLen = 0;


// =====================================================
// MARK: - Utility Helpers
// [TAG: ESP_UTILS]
// =====================================================
static String trimCopy(const String &s) {
  String t = s;
  t.trim();
  return t;
}

static String toLowerCopy(const String &s) {
  String t = s;
  t.toLowerCase();
  return t;
}

static long clampLong(long v, long lo, long hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

static String ellipsize(const String &s, uint8_t maxChars) {
  if (maxChars == 0) return "";
  if (s.length() <= maxChars) return s;
  if (maxChars <= 3) return s.substring(0, maxChars);
  return s.substring(0, maxChars - 3) + "...";
}

static String truncatePx(const String &s, uint8_t textSize, int maxPx) {
  int charPx = 6 * (int)textSize;
  if (charPx < 1) charPx = 6;
  int maxChars = maxPx / charPx;
  if (maxChars < 1) maxChars = 1;
  if (maxChars > 250) maxChars = 250;
  return ellipsize(s, (uint8_t)maxChars);
}

static bool parseBoolLoose(const String &s, bool fallback) {
  String t = toLowerCopy(trimCopy(s));
  if (t == "1" || t == "true" || t == "yes" || t == "on" || t == "done") return true;
  if (t == "0" || t == "false" || t == "no" || t == "off" || t == "idle") return false;
  return fallback;
}

static String fieldAt(const String &payload, uint8_t index) {
  int start = 0;
  uint8_t current = 0;

  for (int i = 0; i <= payload.length(); i++) {
    if (i == payload.length() || payload.charAt(i) == '|') {
      if (current == index) {
        return trimCopy(payload.substring(start, i));
      }
      current++;
      start = i + 1;
    }
  }

  return "";
}

static long toLongOr(const String &s, long defVal) {
  String t = trimCopy(s);
  if (t.length() == 0) return defVal;

  bool valid = true;
  for (int i = 0; i < t.length(); i++) {
    char c = t.charAt(i);
    if (i == 0 && (c == '-' || c == '+')) continue;
    if (!isDigit((unsigned char)c)) {
      valid = false;
      break;
    }
  }

  if (!valid) return defVal;
  return t.toInt();
}

static String formatMMSS(long sec) {
  if (sec < 0) return "--:--";
  int mm = (int)(sec / 60);
  int ss = (int)(sec % 60);
  char buf[16];
  snprintf(buf, sizeof(buf), "%02d:%02d", mm, ss);
  return String(buf);
}

static String upperWord(const String &s) {
  String t = s;
  t.toUpperCase();
  return t;
}

static const char *viewToToken(ViewMode mode) {
  switch (mode) {
    case VIEW_IDLE:     return "idle";
    case VIEW_MUSIC:    return "music";
    case VIEW_FOCUS:    return "focus";
    case VIEW_TASKS:    return "tasks";
    case VIEW_HABITS:   return "habits";
    case VIEW_COACH:    return "coach";
    case VIEW_GAME:     return "game";
    case VIEW_STATS:    return "stats";
    case VIEW_SETTINGS: return "settings";
    default:            return "idle";
  }
}

static const char *viewTitle(ViewMode mode) {
  switch (mode) {
    case VIEW_IDLE:     return "Maddy";
    case VIEW_MUSIC:    return "Music";
    case VIEW_FOCUS:    return "Focus";
    case VIEW_TASKS:    return "Tasks";
    case VIEW_HABITS:   return "Habits";
    case VIEW_COACH:    return "Coach";
    case VIEW_GAME:     return "Gamify";
    case VIEW_STATS:    return "Stats";
    case VIEW_SETTINGS: return "Settings";
    default:            return "Maddy";
  }
}

static ViewMode parseViewMode(const String &raw) {
  String v = toLowerCopy(trimCopy(raw));
  if (v == "idle") return VIEW_IDLE;
  if (v == "music") return VIEW_MUSIC;
  if (v == "focus") return VIEW_FOCUS;
  if (v == "tasks") return VIEW_TASKS;
  if (v == "habits") return VIEW_HABITS;
  if (v == "coach") return VIEW_COACH;
  if (v == "gamify") return VIEW_GAME;
  if (v == "game") return VIEW_GAME;
  if (v == "stats") return VIEW_STATS;
  if (v == "debug") return VIEW_SETTINGS;
  if (v == "settings") return VIEW_SETTINGS;
  return VIEW_IDLE;
}

static AIStyleMode parseAIStyleMode(const String &raw, AIStyleMode fallback) {
  String v = toLowerCopy(trimCopy(raw));
  if (v == "orb") return AI_STYLE_ORB;
  if (v == "face") return AI_STYLE_FACE;
  if (v == "status" || v == "statuscard" || v == "card") return AI_STYLE_STATUS;
  return fallback;
}

static void markContentDirty() {
  contentDirty = true;
}

static void requestFullRedraw() {
  fullRedrawPending = true;
  contentDirty = true;
  topBarDirty = true;
}

static void markRxAlive() {
  lastRxMs = millis();
  if (!linkOk) {
    linkOk = true;
    topBarDirty = true;
  }
}

static bool setIfChangedString(String &dst, const String &src) {
  if (dst != src) {
    dst = src;
    return true;
  }
  return false;
}

static bool setIfChangedInt(int &dst, int src) {
  if (dst != src) {
    dst = src;
    return true;
  }
  return false;
}

static bool setIfChangedLong(long &dst, long src) {
  if (dst != src) {
    dst = src;
    return true;
  }
  return false;
}

static bool setIfChangedBool(bool &dst, bool src) {
  if (dst != src) {
    dst = src;
    return true;
  }
  return false;
}


// =====================================================
// MARK: - Display Init
// [TAG: DISPLAY_INIT]
// =====================================================
static void backlightOn() {
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
}

static void hardResetPanel() {
  pinMode(TFT_RST, OUTPUT);
  digitalWrite(TFT_RST, HIGH);
  delay(10);
  digitalWrite(TFT_RST, LOW);
  delay(30);
  digitalWrite(TFT_RST, HIGH);
  delay(120);
}

static void displayInit() {
  backlightOn();
  hardResetPanel();

  gfx->begin();
  gfx->setRotation(3);
  gfx->fillScreen(C_BG);
}


// =====================================================
// MARK: - Shared UI Primitives
// [TAG: UI_PRIMITIVES]
// =====================================================
static void clearContentArea() {
  gfx->fillRect(0, CONTENT_Y, SCREEN_WIDTH, CONTENT_H, C_BG);
}

static void drawCard(int x, int y, int w, int h) {
  gfx->fillRoundRect(x, y, w, h, 8, C_CARD);
  gfx->drawRoundRect(x, y, w, h, 8, C_BORDER);
}

static void drawTopBar(const char *title) {
  (void)title;
}

static void drawBottomHint(const String &hint) {
  gfx->fillRect(0, BOTTOM_Y, SCREEN_WIDTH, BOTTOM_H, C_BG);
  gfx->drawFastHLine(0, BOTTOM_Y, SCREEN_WIDTH, C_BORDER);

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(10, 156);
  gfx->print(truncatePx(hint, 1, TEXT_MAX_PX));
}

static void drawProgressBar(int x, int y, int w, int percent, uint16_t fillColor) {
  int p = (int)clampLong(percent, 0, 100);
  gfx->fillRoundRect(x, y, w, PROGRESS_H, 3, C_TRACK);
  int fillW = (w * p) / 100;
  if (fillW > 0) {
    gfx->fillRoundRect(x, y, fillW, PROGRESS_H, 3, fillColor);
  }
  gfx->drawRoundRect(x, y, w, PROGRESS_H, 3, C_BORDER);
}

static uint8_t fitTextSize(const String &text, int maxWidthPx, int maxHeightPx, uint8_t preferred) {
  for (int sz = preferred; sz >= 1; sz--) {
    int w = (int)text.length() * 6 * sz;
    int h = 8 * sz;
    if (w <= maxWidthPx && h <= maxHeightPx) {
      return (uint8_t)sz;
    }
  }
  return 1;
}

static void drawHexRing(int cx, int cy, int radius, uint16_t color) {
  int px[6];
  int py[6];
  for (int i = 0; i < 6; i++) {
    float a = (-PI / 2.0f) + ((2.0f * PI * (float)i) / 6.0f);
    px[i] = cx + (int)(cos(a) * (float)radius);
    py[i] = cy + (int)(sin(a) * (float)radius);
  }

  for (int i = 0; i < 6; i++) {
    int j = (i + 1) % 6;
    gfx->drawLine(px[i], py[i], px[j], py[j], color);
  }
}

static void drawGamifyRadar(int cx, int cy, int radius, const int values[6]) {
  // Grid rings
  for (int step = 1; step <= 4; step++) {
    int rr = (radius * step) / 4;
    drawHexRing(cx, cy, rr, C_BORDER);
  }

  // Axes
  for (int i = 0; i < 6; i++) {
    float a = (-PI / 2.0f) + ((2.0f * PI * (float)i) / 6.0f);
    int x = cx + (int)(cos(a) * (float)radius);
    int y = cy + (int)(sin(a) * (float)radius);
    gfx->drawLine(cx, cy, x, y, C_BORDER);
  }

  int px[6];
  int py[6];
  for (int i = 0; i < 6; i++) {
    int vv = (int)clampLong(values[i], 0, 100);
    int rr = (radius * vv) / 100;
    float a = (-PI / 2.0f) + ((2.0f * PI * (float)i) / 6.0f);
    px[i] = cx + (int)(cos(a) * (float)rr);
    py[i] = cy + (int)(sin(a) * (float)rr);
  }

  for (int i = 0; i < 6; i++) {
    int j = (i + 1) % 6;
    gfx->drawLine(px[i], py[i], px[j], py[j], C_ACCENT);
  }

  for (int i = 0; i < 6; i++) {
    gfx->fillCircle(px[i], py[i], 2, C_ACCENT);
  }
}

// =====================================================
// MARK: - Habit Done Animation
// [TAG: HABIT_DONE_ANIM]
// =====================================================
static void startHabitDoneAnimation() {
  habitDoneAnimActive = true;
  habitDoneAnimStartMs = millis();
  habitDoneAnimDurationMs = 900UL + (millis() % 300UL);
}

static void drawHabitDoneAnimation(unsigned long now) {
  if (!habitDoneAnimActive) return;

  unsigned long elapsed = now - habitDoneAnimStartMs;
  if (elapsed >= habitDoneAnimDurationMs) {
    habitDoneAnimActive = false;
    if (viewMode == VIEW_FOCUS) {
      int y = 8;
      gfx->fillRoundRect(SCREEN_WIDTH - 86, y, 76, 20, 6, C_BG);
      contentDirty = true;
    } else {
      topBarDirty = true;
    }
    return;
  }

  float p = (float)elapsed / (float)habitDoneAnimDurationMs;
  float pop = (p < 0.35f) ? (0.85f + p * 0.65f) : (1.15f - (p - 0.35f) * 0.28f);
  int y = (viewMode == VIEW_FOCUS) ? 8 : 2;
  int x = SCREEN_WIDTH - 86;

  uint16_t bg = (viewMode == VIEW_FOCUS) ? C_BG : C_TOPBAR;
  gfx->fillRoundRect(x, y, 76, 20, 6, bg);
  gfx->drawRoundRect(x, y, 76, 20, 6, C_BORDER);

  int cx = x + 18;
  int cy = y + 10;
  int d = (int)(4.0f * pop);
  if (d < 3) d = 3;

  // Checkmark pop
  gfx->drawLine(cx - d, cy, cx - 1, cy + d - 1, C_GOOD);
  gfx->drawLine(cx - d + 1, cy, cx, cy + d - 1, C_GOOD);
  gfx->drawLine(cx - 1, cy + d - 1, cx + d + 2, cy - d, C_GOOD);
  gfx->drawLine(cx, cy + d - 1, cx + d + 3, cy - d, C_GOOD);

  // Tiny sparkle points
  int sparkleOffset = (int)(p * 6.0f);
  gfx->drawPixel(x + 42 + sparkleOffset, y + 6, C_ACCENT);
  gfx->drawPixel(x + 46 + sparkleOffset, y + 12, C_ACCENT);
  gfx->drawPixel(x + 38 + sparkleOffset, y + 14, C_WARN);

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(x + 28, y + 7);
  gfx->print("done");
}


// =====================================================
// MARK: - Draw Idle
// [TAG: DRAW_IDLE]
// =====================================================
static void drawIdle(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 300, 82);
    drawCard(10, 96, 146, 48);
    drawCard(164, 96, 146, 48);

    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(20, 104);
    gfx->print("Now Playing");
    gfx->setCursor(174, 104);
    gfx->print("Focus");

    drawBottomHint("home overview");
  }

  gfx->fillRect(18, 22, 284, 36, C_CARD);
  String c = truncatePx(timeStr, 4, 220);
  int cx = 10 + ((300 - ((int)c.length() * 24)) / 2);
  if (cx < 14) cx = 14;
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(4);
  gfx->setCursor(cx, 30);
  gfx->print(c);

  gfx->fillRect(20, 70, 280, 8, C_CARD);
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 70);
  gfx->print(truncatePx(dateStr.length() ? dateStr : "---- -- --", 1, TEXT_MAX_PX));

  gfx->fillRect(20, 116, 130, 20, C_CARD);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(20, 118);
  gfx->print(truncatePx(musicTitle.length() ? musicTitle : "-", 2, 130));

  String phase = upperWord(pomoPhase);
  if (phase.length() == 0) phase = "FOCUS";
  String focusTxt = phase + " " + formatMMSS(pomoRemaining);

  gfx->fillRect(174, 116, 130, 20, C_CARD);
  gfx->setTextColor(C_ACCENT);
  gfx->setTextSize(2);
  gfx->setCursor(174, 118);
  gfx->print(truncatePx(focusTxt, 2, 130));
}


// =====================================================
// MARK: - Draw Music
// [TAG: DRAW_MUSIC]
// =====================================================
static void drawMusic(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 300, 60);
    drawCard(10, 72, 300, 72);

    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(18, 82);
    gfx->print("Progress");

    drawBottomHint("<   >   ||>");
  }

  String st = toLowerCopy(musicState);
  if (st.length() == 0) st = "stopped";

  uint16_t badgeColor = C_MUTED;
  String badge = "STOPPED";
  if (st == "playing") {
    badgeColor = C_GOOD;
    badge = "PLAYING";
  } else if (st == "paused") {
    badgeColor = C_WARN;
    badge = "PAUSED";
  }

  gfx->fillRect(18, 18, 286, 26, C_CARD);
  gfx->fillRoundRect(18, 18, 86, 16, 4, badgeColor);
  gfx->setTextColor(BLACK);
  gfx->setTextSize(1);
  gfx->setCursor(30, 23);
  gfx->print(badge);

  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(114, 20);
  gfx->print(truncatePx(musicTitle.length() ? musicTitle : "-", 2, 176));

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(114, 40);
  gfx->print(truncatePx(musicArtist.length() ? musicArtist : "-", 1, 176));

  gfx->fillRect(286, 20, 16, 16, C_CARD);
  if (st == "paused") {
    gfx->fillRect(289, 22, 4, 12, C_TEXT);
    gfx->fillRect(295, 22, 4, 12, C_TEXT);
  } else if (st == "playing") {
    gfx->fillTriangle(289, 22, 289, 34, 300, 28, C_TEXT);
  } else {
    gfx->drawRect(289, 22, 10, 10, C_TEXT);
  }

  bool hasProg = (musicDurSec > 0 && musicPosSec >= 0);
  int pct = 0;
  if (hasProg) {
    pct = (int)clampLong((musicPosSec * 100L) / musicDurSec, 0, 100);
  }

  gfx->fillRect(10, 94, 300, 18, C_CARD);
  drawProgressBar(10, 94, 300, hasProg ? pct : 0, C_ACCENT);

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(18, 106);
  if (hasProg) {
    String t = formatMMSS(musicPosSec) + " / " + formatMMSS(musicDurSec);
    gfx->print(truncatePx(t, 1, TEXT_MAX_PX));
  } else {
    gfx->print("--:-- / --:--");
  }

}


// =====================================================
// MARK: - Draw Focus
// [TAG: DRAW_FOCUS]
// [TAG: DRAW_FOCUS_RING]
// =====================================================
static void drawFocus(bool full) {
  const int cx = SCREEN_WIDTH / 2;
  const int cy = SCREEN_HEIGHT / 2;
  const int rOuter = 62;
  const int rInner = 48;
  const int boxX = cx - rOuter - 4;
  const int boxY = cy - rOuter - 4;
  const int boxW = (rOuter * 2) + 8;
  const int boxH = (rOuter * 2) + 8;

  if (full) {
    gfx->fillScreen(C_BG);
  }

  // Region-only redraw to avoid full-screen flicker while progress updates.
  gfx->fillRect(boxX, boxY, boxW, boxH, C_BG);

  float prog = 0.0f;
  if (pomoTotal > 0) {
    prog = 1.0f - ((float)pomoRemaining / (float)pomoTotal);
    if (prog < 0.0f) prog = 0.0f;
    if (prog > 1.0f) prog = 1.0f;
  }

  const int steps = 180;
  int filled = (int)(prog * (float)steps);

  // Base ring track.
  for (int i = 0; i < steps; i++) {
    float a = (float)i / (float)steps * 2.0f * PI - PI / 2.0f;
    int x1 = cx + (int)(cos(a) * rInner);
    int y1 = cy + (int)(sin(a) * rInner);
    int x2 = cx + (int)(cos(a) * rOuter);
    int y2 = cy + (int)(sin(a) * rOuter);
    gfx->drawLine(x1, y1, x2, y2, C_TRACK);
  }

  // Progress arc.
  for (int i = 0; i < steps; i++) {
    float a = (float)i / (float)steps * 2.0f * PI - PI / 2.0f;
    int x1 = cx + (int)(cos(a) * rInner);
    int y1 = cy + (int)(sin(a) * rInner);
    int x2 = cx + (int)(cos(a) * rOuter);
    int y2 = cy + (int)(sin(a) * rOuter);
    if (i <= filled) {
      gfx->drawLine(x1, y1, x2, y2, C_ACCENT);
    }
  }

  // Punch out center to keep timer text clean and non-overlapping.
  gfx->fillCircle(cx, cy, rInner - 2, C_BG);
  gfx->drawCircle(cx, cy, rOuter, C_BORDER);
  gfx->drawCircle(cx, cy, rInner, C_BORDER);

  String t = formatMMSS(pomoRemaining);
  uint8_t textSize = fitTextSize(t, (rInner * 2) - 10, (rInner * 2) - 10, 3);
  int tw = (int)t.length() * 6 * (int)textSize;
  int th = 8 * (int)textSize;
  int tx = cx - (tw / 2);
  int ty = cy - (th / 2);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(textSize);
  gfx->setCursor(tx, ty);
  gfx->print(t);
}


// =====================================================
// MARK: - Draw Tasks
// [TAG: DRAW_TASKS]
// =====================================================
static void drawTasks(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 146, 58);
    drawCard(164, 8, 146, 58);
    drawCard(10, 72, 300, 72);

    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(20, 18);
    gfx->print("Open tasks");
    gfx->setCursor(174, 18);
    gfx->print("Due soon");

    drawBottomHint("tasks summary");
  }

  gfx->fillRect(20, 36, 120, 20, C_CARD);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(20, 38);
  gfx->print(String(tasksOpenCount));

  gfx->fillRect(174, 36, 120, 20, C_CARD);
  gfx->setTextColor(C_WARN);
  gfx->setCursor(174, 38);
  gfx->print(String(tasksDueSoonCount));

  gfx->fillRect(20, 102, 280, 8, C_CARD);
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 102);
  gfx->print(truncatePx("Start Focus from task in app", 1, TEXT_MAX_PX));
}


// =====================================================
// MARK: - Draw Habits
// [TAG: DRAW_HABITS]
// =====================================================
static void drawHabits(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 146, 58);
    drawCard(164, 8, 146, 58);
    drawCard(10, 72, 300, 72);

    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(20, 18);
    gfx->print("Done today");
    gfx->setCursor(174, 18);
    gfx->print("Streak");

    gfx->setCursor(20, 84);
    gfx->print("Week");

    drawBottomHint("habits progress");
  }

  gfx->fillRect(20, 36, 120, 20, C_CARD);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  String done = String(habitsDoneToday) + "/" + String(habitsTotalToday);
  gfx->setCursor(20, 38);
  gfx->print(truncatePx(done, 2, 120));

  gfx->fillRect(174, 36, 120, 20, C_CARD);
  gfx->setTextColor(C_WARN);
  gfx->setCursor(174, 38);
  gfx->print(String(habitsStreak) + " d");

  int filled = 0;
  if (habitsTotalToday > 0) {
    filled = (int)clampLong((habitsDoneToday * 7L) / habitsTotalToday, 0, 7);
  }

  gfx->fillRect(20, 98, 280, 14, C_CARD);
  for (int i = 0; i < 7; i++) {
    int bx = 20 + (i * 42);
    uint16_t col = (i < filled) ? C_GOOD : C_TRACK;
    gfx->fillRoundRect(bx, 98, 24, 14, 3, col);
    gfx->drawRoundRect(bx, 98, 24, 14, 3, C_BORDER);
  }

}


// =====================================================
// MARK: - Draw Coach
// [TAG: DRAW_COACH]
// =====================================================
static void drawCoachOrbDesign(unsigned long nowMs) {
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 18);
  gfx->print("AI Placeholder");

  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(20, 30);
  gfx->print("Orb");

  int cx = SCREEN_WIDTH / 2;
  int cy = 102;
  int baseR = 20;
  float phase = (float)(nowMs % 5000UL) / 5000.0f;
  float pulse = 0.5f + 0.5f * sinf(phase * 2.0f * PI);
  int r1 = baseR + (int)(pulse * 8.0f);
  int r2 = baseR + 14 + (int)(pulse * 5.0f);

  gfx->drawCircle(cx, cy, r2, C_BORDER);
  gfx->drawCircle(cx, cy, r1, C_ACCENT);
  gfx->fillCircle(cx, cy, baseR - 2, C_CARD);
  gfx->drawCircle(cx, cy, baseR, C_ACCENT);

  float orbitA = ((float)(nowMs % 3600UL) / 3600.0f) * 2.0f * PI;
  int ox = cx + (int)(cosf(orbitA) * (float)(r2 - 2));
  int oy = cy + (int)(sinf(orbitA) * (float)(r2 - 2));
  gfx->fillCircle(ox, oy, 3, C_GOOD);

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 132);
  gfx->print(truncatePx(coachHint.length() ? coachHint : "Ready...", 1, TEXT_MAX_PX));
}

static void drawCoachFaceDesign(unsigned long nowMs) {
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 18);
  gfx->print("AI Placeholder");

  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(20, 30);
  gfx->print("Face");

  int cx = SCREEN_WIDTH / 2;
  int cy = 96;
  int headR = 32;

  gfx->drawCircle(cx, cy, headR, C_ACCENT);
  gfx->drawCircle(cx, cy, headR - 1, C_BORDER);

  bool blink = ((nowMs / 2200UL) % 6UL) == 0UL;
  if (blink) {
    gfx->drawLine(cx - 14, cy - 8, cx - 6, cy - 8, C_TEXT);
    gfx->drawLine(cx + 6, cy - 8, cx + 14, cy - 8, C_TEXT);
  } else {
    gfx->fillCircle(cx - 10, cy - 8, 3, C_TEXT);
    gfx->fillCircle(cx + 10, cy - 8, 3, C_TEXT);
  }

  int smileY = cy + 10;
  gfx->drawLine(cx - 11, smileY, cx - 4, smileY + 4, C_GOOD);
  gfx->drawLine(cx - 4, smileY + 4, cx + 4, smileY + 4, C_GOOD);
  gfx->drawLine(cx + 4, smileY + 4, cx + 11, smileY, C_GOOD);

  int bob = (int)(sinf((float)(nowMs % 3000UL) / 3000.0f * 2.0f * PI) * 2.0f);
  gfx->fillRoundRect(cx - 6, cy - headR - 10 + bob, 12, 6, 3, C_WARN);

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 132);
  gfx->print(truncatePx("Status: " + coachStatus, 1, TEXT_MAX_PX));
}

static void drawCoachStatusDesign(unsigned long nowMs) {
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 18);
  gfx->print("AI Placeholder");

  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(20, 30);
  gfx->print("Status Card");

  String st = toLowerCopy(coachStatus);
  if (st.length() == 0) st = "idle";

  uint16_t stColor = C_TEXT;
  if (st == "thinking") stColor = C_WARN;
  else if (st == "reply") stColor = C_GOOD;

  gfx->fillRoundRect(24, 70, 84, 18, 5, C_TRACK);
  gfx->drawRoundRect(24, 70, 84, 18, 5, C_BORDER);
  gfx->setTextColor(stColor);
  gfx->setTextSize(1);
  gfx->setCursor(30, 76);
  gfx->print(truncatePx(st, 1, 70));

  int stage = (int)((nowMs / 500UL) % 3UL);
  for (int i = 0; i < 3; i++) {
    int x = 128 + i * 56;
    uint16_t c = (i <= stage) ? C_ACCENT : C_TRACK;
    gfx->fillRoundRect(x, 74, 40, 10, 4, c);
    gfx->drawRoundRect(x, 74, 40, 10, 4, C_BORDER);
    if (i < 2) {
      gfx->drawLine(x + 40, 79, x + 52, 79, C_BORDER);
    }
  }

  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(24, 104);
  gfx->print("Hint");

  gfx->setTextColor(C_TEXT);
  gfx->setCursor(24, 118);
  gfx->print(truncatePx(coachHint.length() ? coachHint : "-", 1, TEXT_MAX_PX));
}

static void drawCoach(bool full) {
  unsigned long nowMs = millis();
  if (full) {
    clearContentArea();
    drawBottomHint("coach hint");
  }

  drawCard(10, 8, 300, 44);
  drawCard(10, 56, 300, 88);

  if (aiStyleMode == AI_STYLE_FACE) {
    drawCoachFaceDesign(nowMs);
  } else if (aiStyleMode == AI_STYLE_STATUS) {
    drawCoachStatusDesign(nowMs);
  } else {
    drawCoachOrbDesign(nowMs);
  }
}


// =====================================================
// MARK: - Draw Game
// [TAG: DRAW_GAME]
// =====================================================
static void drawGame(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 300, 136);
    drawBottomHint("level + radar");
  }

  gfx->fillRect(20, 18, 280, 14, C_CARD);
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 18);
  gfx->print("Gamify");

  gfx->fillRect(208, 16, 92, 18, C_CARD);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(208, 18);
  if (gameHasGamifyData) {
    gfx->print("Lv " + String(gameLevel));
  } else {
    gfx->print("Lv --");
  }

  int cx = 96;
  int cy = 86;
  int radius = 42;

  int vals[6];
  for (int i = 0; i < 6; i++) {
    vals[i] = gameHasGamifyData ? (int)clampLong(gameRadar[i], 0, 100) : 0;
  }
  drawGamifyRadar(cx, cy, radius, vals);

  gfx->fillRect(166, 58, 134, 72, C_CARD);
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(166, 58);
  gfx->print("Axes 0..100");

  const char *labels[6] = {"Foc", "Con", "Dis", "Plan", "Hlt", "Lrn"};
  for (int i = 0; i < 6; i++) {
    int row = i / 2;
    int col = i % 2;
    int x = 166 + (col * 66);
    int y = 72 + (row * 16);
    gfx->setTextColor(C_TEXT);
    gfx->setCursor(x, y);
    String item = String(labels[i]) + " " + String(vals[i]);
    gfx->print(truncatePx(item, 1, 62));
  }

  if (!gameHasGamifyData) {
    gfx->fillRect(166, 122, 134, 8, C_CARD);
    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(166, 122);
    gfx->print("Waiting for gamify...");
  }
}


// =====================================================
// MARK: - Draw Stats
// [TAG: DRAW_STATS]
// =====================================================
static void drawStats(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 96, 68);
    drawCard(112, 8, 96, 68);
    drawCard(214, 8, 96, 68);
    drawCard(10, 82, 300, 62);

    gfx->setTextColor(C_MUTED);
    gfx->setTextSize(1);
    gfx->setCursor(18, 18);
    gfx->print("Today");
    gfx->setCursor(120, 18);
    gfx->print("Week");
    gfx->setCursor(222, 18);
    gfx->print("Month");

    gfx->setCursor(18, 56);
    gfx->print("min");
    gfx->setCursor(120, 56);
    gfx->print("min");
    gfx->setCursor(222, 56);
    gfx->print("min");

    drawBottomHint("today week month");
  }

  gfx->fillRect(18, 36, 84, 16, C_CARD);
  gfx->fillRect(120, 36, 84, 16, C_CARD);
  gfx->fillRect(222, 36, 84, 16, C_CARD);
  gfx->setTextColor(C_TEXT);
  gfx->setTextSize(2);
  gfx->setCursor(18, 36);
  gfx->print(truncatePx(String(statsTodayMin), 2, 84));
  gfx->setCursor(120, 36);
  gfx->print(truncatePx(String(statsWeekMin), 2, 84));
  gfx->setCursor(222, 36);
  gfx->print(truncatePx(String(statsMonthMin), 2, 84));

  int t = statsTodayMin;
  int w = statsWeekMin;
  int m = statsMonthMin;
  int maxVal = t;
  if (w > maxVal) maxVal = w;
  if (m > maxVal) maxVal = m;
  if (maxVal < 1) maxVal = 1;

  int baseY = 136;
  int h1 = (t * 20) / maxVal;
  int h2 = (w * 20) / maxVal;
  int h3 = (m * 20) / maxVal;
  if (h1 < 1) h1 = 1;
  if (h2 < 1) h2 = 1;
  if (h3 < 1) h3 = 1;

  gfx->fillRect(16, 98, 288, 40, C_CARD);
  gfx->fillRect(88, baseY - h1, 14, h1, C_TEXT);
  gfx->fillRect(154, baseY - h2, 14, h2, C_ACCENT);
  gfx->fillRect(220, baseY - h3, 14, h3, C_GOOD);
}


// =====================================================
// MARK: - Draw Settings
// [TAG: DRAW_SETTINGS]
// =====================================================
static void drawSettings(bool full) {
  if (full) {
    clearContentArea();
    drawCard(10, 8, 300, 52);
    drawCard(10, 64, 300, 52);
    drawCard(10, 120, 300, 24);
    drawBottomHint("settings");
  }

  int b = (int)clampLong(settingsBrightness, 0, 100);
  int v = (int)clampLong(settingsVolume, 0, 100);

  gfx->fillRect(20, 18, 280, 8, C_CARD);
  gfx->setTextColor(C_MUTED);
  gfx->setTextSize(1);
  gfx->setCursor(20, 18);
  gfx->print("Brightness " + String(b) + "%");
  gfx->fillRect(10, 40, 300, PROGRESS_H, C_CARD);
  drawProgressBar(10, 40, 300, b, C_ACCENT);

  gfx->fillRect(20, 74, 280, 8, C_CARD);
  gfx->setCursor(20, 74);
  gfx->print("Volume " + String(v) + "%");
  gfx->fillRect(10, 96, 300, PROGRESS_H, C_CARD);
  drawProgressBar(10, 96, 300, v, C_WARN);

  String usb = toLowerCopy(settingsUsb);
  if (usb.length() == 0) usb = "ok";
  uint16_t usbColor = (usb == "ok") ? C_GOOD : C_WARN;

  gfx->setTextColor(C_MUTED);
  gfx->setCursor(20, 126);
  gfx->print("USB");

  gfx->fillRect(60, 126, 250, 8, C_CARD);
  gfx->setTextColor(usbColor);
  gfx->setTextSize(1);
  gfx->setCursor(60, 126);
  gfx->print(truncatePx(usb, 1, 250));
}

// Compatibility wrappers with the requested zero-arg names.
static void drawIdle() { drawIdle(false); }
static void drawMusic() { drawMusic(false); }
static void drawFocus() { drawFocus(false); }
static void drawTasks() { drawTasks(false); }
static void drawHabits() { drawHabits(false); }
static void drawCoach() { drawCoach(false); }
static void drawGame() { drawGame(false); }
static void drawStats() { drawStats(false); }
static void drawSettings() { drawSettings(false); }


// =====================================================
// MARK: - Draw Router
// [TAG: DRAW_ROUTER]
// =====================================================
static void drawCurrentView(bool full) {
  switch (viewMode) {
    case VIEW_IDLE:     drawIdle(full); break;
    case VIEW_MUSIC:    drawMusic(full); break;
    case VIEW_FOCUS:    drawFocus(full); break;
    case VIEW_TASKS:    drawTasks(full); break;
    case VIEW_HABITS:   drawHabits(full); break;
    case VIEW_COACH:    drawCoach(full); break;
    case VIEW_GAME:     drawGame(full); break;
    case VIEW_STATS:    drawStats(full); break;
    case VIEW_SETTINGS: drawSettings(full); break;
    default:            drawIdle(full); break;
  }
}


// =====================================================
// MARK: - Protocol Out
// [TAG: SERIAL_TX]
// =====================================================
static void sendHello() {
  Serial.print("hello:esp|proto=2|fw=1.0|screen=");
  Serial.println(viewToToken(viewMode));
}

static void sendStatus() {
  Serial.print("status:");
  Serial.print(viewToToken(viewMode));
  Serial.print("|uptime=");
  Serial.println(millis() / 1000UL);
}


// =====================================================
// MARK: - Serial Parse
// [TAG: SERIAL_PARSE]
// =====================================================
static void setViewMode(ViewMode next) {
  if (next != viewMode) {
    viewMode = next;
    requestFullRedraw();
  }
}

static void handleLine(const String &lineRaw) {
  String line = trimCopy(lineRaw);
  if (line.length() == 0) return;

  dbgLastLine = ellipsize(line, 80);
  markRxAlive();

  String lower = toLowerCopy(line);

  if (lower == "ping") {
    Serial.println("pong");
    return;
  }

  if (lower.startsWith("disp:reinit")) {
    displayInit();
    requestFullRedraw();
    return;
  }

  if (lower.startsWith("view:")) {
    ViewMode next = parseViewMode(line.substring(5));
    setViewMode(next);
    return;
  }

  if (lower.startsWith("time:")) {
    bool changed = false;
    String payload = line.substring(5);
    String t = fieldAt(payload, 0);
    if (t.length() == 0) t = trimCopy(payload);
    changed |= setIfChangedString(timeStr, t);

    String d = fieldAt(payload, 1);
    if (d.length() > 0) {
      changed |= setIfChangedString(dateStr, d);
    }

    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("date:")) {
    if (setIfChangedString(dateStr, trimCopy(line.substring(5)))) {
      markContentDirty();
    }
    return;
  }

  if (lower.startsWith("music:")) {
    bool changed = false;
    String payload = line.substring(6);
    String f0 = fieldAt(payload, 0);
    String f1 = fieldAt(payload, 1);
    String f2 = fieldAt(payload, 2);
    String f3 = fieldAt(payload, 3);
    String f4 = fieldAt(payload, 4);

    if (f0.length()) changed |= setIfChangedString(musicState, toLowerCopy(f0));
    if (f1.length()) changed |= setIfChangedString(musicArtist, f1);
    if (f2.length()) changed |= setIfChangedString(musicTitle, f2);

    long pos = (f3.length() ? toLongOr(f3, -1) : -1);
    long dur = (f4.length() ? toLongOr(f4, -1) : -1);
    if (pos < 0 || dur <= 0) {
      pos = -1;
      dur = -1;
    }
    changed |= setIfChangedLong(musicPosSec, pos);
    changed |= setIfChangedLong(musicDurSec, dur);

    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("pomo:")) {
    bool changed = false;
    String payload = line.substring(5);
    String f0 = fieldAt(payload, 0);
    String f1 = fieldAt(payload, 1);
    String f2 = fieldAt(payload, 2);
    String f3 = fieldAt(payload, 3);

    if (f0.length()) changed |= setIfChangedString(pomoPhase, toLowerCopy(f0));
    changed |= setIfChangedInt(pomoRemaining, (int)clampLong(toLongOr(f1, pomoRemaining), 0, 86399));
    changed |= setIfChangedInt(pomoTotal, (int)clampLong(toLongOr(f2, pomoTotal), 1, 86399));

    String run = toLowerCopy(f3);
    if (run.length()) {
      changed |= setIfChangedBool(pomoRunning, (run == "1" || run == "true" || run == "running"));
    }

    lastPomoTickMs = millis();
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("tasks:")) {
    bool changed = false;
    String payload = line.substring(6);
    changed |= setIfChangedInt(tasksOpenCount, (int)clampLong(toLongOr(fieldAt(payload, 0), tasksOpenCount), 0, 9999));
    changed |= setIfChangedInt(tasksDueSoonCount, (int)clampLong(toLongOr(fieldAt(payload, 1), tasksDueSoonCount), 0, 9999));
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("habits:")) {
    bool changed = false;
    String payload = line.substring(7);
    changed |= setIfChangedInt(habitsDoneToday, (int)clampLong(toLongOr(fieldAt(payload, 0), habitsDoneToday), 0, 999));
    changed |= setIfChangedInt(habitsTotalToday, (int)clampLong(toLongOr(fieldAt(payload, 1), habitsTotalToday), 0, 999));
    changed |= setIfChangedInt(habitsStreak, (int)clampLong(toLongOr(fieldAt(payload, 2), habitsStreak), 0, 9999));
    if (changed) markContentDirty();
    return;
  }

  // =====================================================
  // MARK: - Habit Done Parse
  // [TAG: SERIAL_PARSE_HABIT_DONE]
  // =====================================================
  if (lower.startsWith("habit_done:")) {
    String donePayload = trimCopy(line.substring(11));
    if (donePayload.length() > 0) {
      dbgLastLine = "habit_done:" + ellipsize(donePayload, 40);
    }
    startHabitDoneAnimation();
    return;
  }

  if (lower.startsWith("habit:")) {
    bool changed = false;
    String payload = line.substring(6);
    String f0 = fieldAt(payload, 0);
    String f1 = fieldAt(payload, 1);
    String f2 = fieldAt(payload, 2);
    String f3 = fieldAt(payload, 3);
    String f4 = fieldAt(payload, 4);
    String f5 = fieldAt(payload, 5);

    if (f0.length()) changed |= setIfChangedString(selectedHabitId, f0);
    if (f1.length()) changed |= setIfChangedString(selectedHabitTitle, f1);
    if (f2.length()) changed |= setIfChangedString(selectedHabitSymbol, f2);
    if (f3.length()) changed |= setIfChangedString(selectedHabitColor, f3);
    if (f4.length()) changed |= setIfChangedInt(selectedHabitStreak, (int)clampLong(toLongOr(f4, selectedHabitStreak), 0, 9999));
    if (f5.length()) {
      bool done = parseBoolLoose(f5, selectedHabitDoneToday != 0);
      changed |= setIfChangedInt(selectedHabitDoneToday, done ? 1 : 0);
    }

    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("ai_style:")) {
    AIStyleMode nextStyle = parseAIStyleMode(line.substring(9), aiStyleMode);
    if (nextStyle != aiStyleMode) {
      aiStyleMode = nextStyle;
      markContentDirty();
    }
    return;
  }

  if (lower.startsWith("coach:")) {
    bool changed = false;
    String payload = line.substring(6);
    String f0 = fieldAt(payload, 0);
    String f1 = fieldAt(payload, 1);
    if (f0.length()) changed |= setIfChangedString(coachStatus, toLowerCopy(f0));
    if (f1.length()) changed |= setIfChangedString(coachHint, f1);
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("gamify:")) {
    bool changed = false;
    String payload = line.substring(7);

    String fields[7];
    bool hasAnyField = false;
    for (int i = 0; i < 7; i++) {
      fields[i] = fieldAt(payload, (uint8_t)i);
      if (fields[i].length() > 0) {
        hasAnyField = true;
      }
    }

    if (!hasAnyField) {
      return;
    }

    changed |= setIfChangedInt(gameLevel, (int)clampLong(toLongOr(fields[0], gameLevel), 0, 9999));
    for (int i = 0; i < 6; i++) {
      changed |= setIfChangedInt(gameRadar[i], (int)clampLong(toLongOr(fields[i + 1], gameRadar[i]), 0, 100));
    }

    changed |= setIfChangedBool(gameHasGamifyData, true);
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("game:")) {
    bool changed = false;
    String payload = line.substring(5);
    changed |= setIfChangedInt(gameLevel, (int)clampLong(toLongOr(fieldAt(payload, 0), gameLevel), 1, 999));
    changed |= setIfChangedInt(gameXp, (int)clampLong(toLongOr(fieldAt(payload, 1), gameXp), 0, 999999));
    changed |= setIfChangedInt(gameStreak, (int)clampLong(toLongOr(fieldAt(payload, 2), gameStreak), 0, 9999));
    changed |= setIfChangedInt(gameSkillFocus, (int)clampLong(toLongOr(fieldAt(payload, 3), gameSkillFocus), 0, 100));
    changed |= setIfChangedInt(gameSkillLearning, (int)clampLong(toLongOr(fieldAt(payload, 4), gameSkillLearning), 0, 100));
    changed |= setIfChangedInt(gameSkillConsistency, (int)clampLong(toLongOr(fieldAt(payload, 5), gameSkillConsistency), 0, 100));
    changed |= setIfChangedInt(gameRadar[0], gameSkillFocus);
    changed |= setIfChangedInt(gameRadar[1], gameSkillConsistency);
    changed |= setIfChangedInt(gameRadar[2], gameSkillLearning);
    changed |= setIfChangedInt(gameRadar[3], gameSkillFocus);
    changed |= setIfChangedInt(gameRadar[4], gameSkillConsistency);
    changed |= setIfChangedInt(gameRadar[5], gameSkillLearning);
    changed |= setIfChangedBool(gameHasGamifyData, true);
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("stats:")) {
    bool changed = false;
    String payload = line.substring(6);
    changed |= setIfChangedInt(statsTodayMin, (int)clampLong(toLongOr(fieldAt(payload, 0), statsTodayMin), 0, 100000));
    changed |= setIfChangedInt(statsWeekMin, (int)clampLong(toLongOr(fieldAt(payload, 1), statsWeekMin), 0, 100000));
    changed |= setIfChangedInt(statsMonthMin, (int)clampLong(toLongOr(fieldAt(payload, 2), statsMonthMin), 0, 100000));
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("settings:")) {
    bool changed = false;
    String payload = line.substring(9);
    changed |= setIfChangedInt(settingsBrightness, (int)clampLong(toLongOr(fieldAt(payload, 0), settingsBrightness), 0, 100));
    changed |= setIfChangedInt(settingsVolume, (int)clampLong(toLongOr(fieldAt(payload, 1), settingsVolume), 0, 100));
    String u = fieldAt(payload, 2);
    if (u.length()) changed |= setIfChangedString(settingsUsb, toLowerCopy(u));
    if (changed) markContentDirty();
    return;
  }

  if (lower.startsWith("dbg:")) {
    dbgLastLine = trimCopy(line.substring(4));
    return;
  }

  dbgLastError = "Unknown cmd: " + ellipsize(line, 20);
}

static void serialPoll() {
  uint16_t processed = 0;
  while (Serial.available() && processed < RX_BYTES_PER_POLL) {
    char c = (char)Serial.read();
    processed++;

    if (c == '\n') {
      inLine[inLineLen] = '\0';
      handleLine(String(inLine));
      inLineLen = 0;
    } else if (c != '\r') {
      if (inLineLen < (RX_LINE_MAX - 1)) {
        inLine[inLineLen++] = c;
      } else {
        inLineLen = 0;
        dbgLastError = "RX overflow";
      }
    }
  }
}


void setup() {
  Serial.begin(115200);
  delay(200);

  displayInit();
  viewMode = VIEW_IDLE;
  requestFullRedraw();

  lastRxMs = millis();
  lastStatusMs = millis();
  lastFrameMs = 0;

  sendHello();
}

void loop() {
  serialPoll();

  unsigned long now = millis();

  if (linkOk && (now - lastRxMs) > RX_TIMEOUT_MS) {
    linkOk = false;
    topBarDirty = true;
  }

  if ((now - lastStatusMs) >= STATUS_INTERVAL_MS) {
    lastStatusMs = now;
    sendStatus();
  }

  // =====================================================
  // MARK: - Pomo Progress Update
  // [TAG: POMO_PROGRESS_UPDATE]
  // =====================================================
  if (pomoRunning && pomoRemaining > 0) {
    if (lastPomoTickMs == 0) {
      lastPomoTickMs = now;
    } else if ((now - lastPomoTickMs) >= 1000UL) {
      unsigned long ticks = (now - lastPomoTickMs) / 1000UL;
      lastPomoTickMs += ticks * 1000UL;

      int nextRemaining = pomoRemaining - (int)ticks;
      if (nextRemaining < 0) nextRemaining = 0;
      if (nextRemaining != pomoRemaining) {
        pomoRemaining = nextRemaining;
        markContentDirty();
      }
    }
  } else {
    lastPomoTickMs = now;
  }

  if (viewMode == VIEW_COACH) {
    if ((now - lastCoachAnimMs) >= 120UL) {
      lastCoachAnimMs = now;
      markContentDirty();
    }
  }

  if ((now - lastFrameMs) >= FRAME_INTERVAL_MS) {
    lastFrameMs = now;

    if (fullRedrawPending) {
      gfx->fillScreen(C_BG);
      if (viewMode != VIEW_FOCUS) {
        drawTopBar(viewTitle(viewMode));
      }
      drawCurrentView(true);
      fullRedrawPending = false;
      topBarDirty = false;
      contentDirty = false;
    } else {
      if (topBarDirty && viewMode != VIEW_FOCUS) {
        drawTopBar(viewTitle(viewMode));
        topBarDirty = false;
      }
      if (topBarDirty && viewMode == VIEW_FOCUS) {
        topBarDirty = false;
      }
      if (contentDirty) {
        drawCurrentView(false);
        contentDirty = false;
      }
    }

    if (habitDoneAnimActive) {
      drawHabitDoneAnimation(now);
    }
  }

  delay(1);
}
