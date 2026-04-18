// ============================================================
// gp_keypad — GuardianPlay phone-style PIN keypad
// ============================================================
// Usage:  gp_keypad "<title>" "<message>"
// Exit:   0..9  = digit pressed
//         255   = cancelled (B or MENU)
// ============================================================

#include <SDL/SDL.h>
#include <SDL/SDL_ttf.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define SCREEN_W 640
#define SCREEN_H 480

#define ROWS 4
#define COLS 3

// Phone keypad: 10 cells, (row, col, digit, enabled)
// Row 3 only has the centre column (digit 0); left/right cells are disabled.
typedef struct { int row, col, digit, enabled; } Cell;
static Cell cells[] = {
    {0,0,1,1},{0,1,2,1},{0,2,3,1},
    {1,0,4,1},{1,1,5,1},{1,2,6,1},
    {2,0,7,1},{2,1,8,1},{2,2,9,1},
    {3,0,0,0},{3,1,0,1},{3,2,0,0}
};
#define N_CELLS (sizeof(cells)/sizeof(cells[0]))

static TTF_Font *open_font(int size) {
    const char *paths[] = {
        "/mnt/SDCARD/App/ParentalControl/res/font.ttf",
        "/mnt/SDCARD/miyoo/app/Helvetica-Neue.ttf",
        "/customer/app/Helvetica-Neue.ttf",
        "/mnt/SDCARD/.tmp_update/res/fonts/OnionFont.ttf",
        NULL
    };
    for (int i = 0; paths[i]; i++) {
        TTF_Font *f = TTF_OpenFont(paths[i], size);
        if (f) return f;
    }
    return NULL;
}

static void draw_text_centered(SDL_Surface *dst, TTF_Font *f, const char *s,
                               int cx, int cy, SDL_Color col) {
    if (!s || !*s) return;
    SDL_Surface *t = TTF_RenderUTF8_Blended(f, s, col);
    if (!t) return;
    SDL_Rect r = { cx - t->w/2, cy - t->h/2, 0, 0 };
    SDL_BlitSurface(t, NULL, dst, &r);
    SDL_FreeSurface(t);
}

static void fill_rect(SDL_Surface *dst, int x, int y, int w, int h, Uint32 c) {
    SDL_Rect r = { x, y, w, h };
    SDL_FillRect(dst, &r, c);
}

static int find_cell(int row, int col) {
    for (size_t i = 0; i < N_CELLS; i++)
        if (cells[i].enabled && cells[i].row == row && cells[i].col == col)
            return (int)i;
    return -1;
}

// Move selection in a direction; skip disabled cells.
static int move(int cur, int drow, int dcol) {
    int r = cells[cur].row + drow;
    int c = cells[cur].col + dcol;
    // Step until we land on a valid cell or fall off the grid
    while (r >= 0 && r < ROWS && c >= 0 && c < COLS) {
        int n = find_cell(r, c);
        if (n >= 0) return n;
        r += drow; c += dcol;
    }
    return cur;
}

int main(int argc, char *argv[]) {
    const char *title   = (argc > 1) ? argv[1] : "PIN Code";
    const char *message = (argc > 2) ? argv[2] : "";

    if (SDL_Init(SDL_INIT_VIDEO) != 0) return 255;
    if (TTF_Init() != 0) { SDL_Quit(); return 255; }

    SDL_Surface *screen = SDL_SetVideoMode(SCREEN_W, SCREEN_H, 32, SDL_HWSURFACE);
    if (!screen) { TTF_Quit(); SDL_Quit(); return 255; }
    SDL_ShowCursor(SDL_DISABLE);

    TTF_Font *f_title = open_font(28);
    TTF_Font *f_msg   = open_font(18);
    TTF_Font *f_digit = open_font(44);
    if (!f_title || !f_msg || !f_digit) { TTF_Quit(); SDL_Quit(); return 255; }

    SDL_Color white  = {255,255,255,0};
    SDL_Color grey   = {180,180,180,0};
    SDL_Color yellow = {255,210,0,0};

    Uint32 c_bg     = SDL_MapRGB(screen->format,  20, 20, 30);
    Uint32 c_cell   = SDL_MapRGB(screen->format,  50, 55, 75);
    Uint32 c_cellhi = SDL_MapRGB(screen->format, 255,210,  0);
    Uint32 c_border = SDL_MapRGB(screen->format, 100,110,140);

    // Start selection on digit 5 (centre) — nicest default for phone layout
    int sel = find_cell(1, 1);
    if (sel < 0) sel = 0;

    int running = 1;
    int result  = 255; // default = cancel

    // Compute keypad geometry
    const int cell_w = 130, cell_h = 70, pad = 14;
    const int grid_w = COLS * cell_w + (COLS - 1) * pad;
    const int grid_h = ROWS * cell_h + (ROWS - 1) * pad;
    const int grid_x = (SCREEN_W - grid_w) / 2;
    const int grid_y = 160;

    while (running) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_QUIT) { result = 255; running = 0; }
            if (ev.type == SDL_KEYDOWN) {
                SDLKey k = ev.key.keysym.sym;
                // Miyoo Mini keymap (Onion): A=SPACE, B=LCTRL, MENU=ESCAPE
                if      (k == SDLK_UP)    sel = move(sel, -1,  0);
                else if (k == SDLK_DOWN)  sel = move(sel, +1,  0);
                else if (k == SDLK_LEFT)  sel = move(sel,  0, -1);
                else if (k == SDLK_RIGHT) sel = move(sel,  0, +1);
                else if (k == SDLK_SPACE || k == SDLK_RETURN) {
                    result = cells[sel].digit;
                    running = 0;
                }
                else if (k == SDLK_LCTRL || k == SDLK_ESCAPE) {
                    result = 255;
                    running = 0;
                }
                // Direct digit shortcut for USB keyboards
                else if (k >= SDLK_0 && k <= SDLK_9) {
                    result = (int)(k - SDLK_0);
                    running = 0;
                }
            }
        }

        // --- Draw ---
        SDL_FillRect(screen, NULL, c_bg);

        // Title
        draw_text_centered(screen, f_title, title, SCREEN_W/2, 30, yellow);
        // Message (may contain one \n for a 2-line layout)
        if (message && *message) {
            char buf[256];
            strncpy(buf, message, sizeof(buf)-1);
            buf[sizeof(buf)-1] = '\0';
            char *line2 = strchr(buf, '\n');
            if (line2) { *line2 = '\0'; line2++; }
            draw_text_centered(screen, f_msg, buf, SCREEN_W/2, 80, white);
            if (line2)
                draw_text_centered(screen, f_msg, line2, SCREEN_W/2, 108, grey);
        }

        // Draw cells
        for (size_t i = 0; i < N_CELLS; i++) {
            if (!cells[i].enabled) continue;
            int x = grid_x + cells[i].col * (cell_w + pad);
            int y = grid_y + cells[i].row * (cell_h + pad);
            Uint32 fill = ((int)i == sel) ? c_cellhi : c_cell;
            // Border
            fill_rect(screen, x-2, y-2, cell_w+4, cell_h+4, c_border);
            fill_rect(screen, x,   y,   cell_w,   cell_h,   fill);
            // Digit
            char d[2] = { (char)('0' + cells[i].digit), 0 };
            SDL_Color tc = ((int)i == sel) ? (SDL_Color){20,20,30,0} : white;
            draw_text_centered(screen, f_digit, d, x + cell_w/2, y + cell_h/2, tc);
        }

        SDL_Flip(screen);
        SDL_Delay(16);
    }

    TTF_CloseFont(f_title);
    TTF_CloseFont(f_msg);
    TTF_CloseFont(f_digit);
    TTF_Quit();
    SDL_Quit();
    return result;
}
