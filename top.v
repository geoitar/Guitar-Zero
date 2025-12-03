`timescale 1ns/1ps

module top (
    input         CLOCK_50,   // 50 MHz board clock
    input  [3:0]  KEY,        // active-LOW pushbuttons
    input  [9:0]  SW,         // SW[9] = reset

    output [9:0]  LEDR,

    output [7:0]  VGA_R,
    output [7:0]  VGA_G,
    output [7:0]  VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_CLK,
    output        VGA_BLANK_N,
    output        VGA_SYNC_N,

    output        pfm         // audio disabled (tied low)
);

    // =========================================================
    // 25 MHz pixel clock from 50 MHz
    // =========================================================
    reg pix_clk = 1'b0;
    always @(posedge CLOCK_50) begin
        pix_clk <= ~pix_clk;  // 50 MHz / 2 = 25 MHz
    end

    assign VGA_CLK = pix_clk;

    // =========================================================
    // Reset (SW9 high = reset)
    // =========================================================
    wire reset = SW[9];

    // =========================================================
    // VGA timing for 640x480 @60 Hz
    // =========================================================
    localparam H_VISIBLE   = 640;
    localparam H_FRONT_POR = 16;
    localparam H_SYNC_PW   = 96;
    localparam H_BACK_POR  = 48;
    localparam H_TOTAL     = H_VISIBLE + H_FRONT_POR + H_SYNC_PW + H_BACK_POR; // 800

    localparam V_VISIBLE   = 480;
    localparam V_FRONT_POR = 10;
    localparam V_SYNC_PW   = 2;
    localparam V_BACK_POR  = 33;
    localparam V_TOTAL     = V_VISIBLE + V_FRONT_POR + V_SYNC_PW + V_BACK_POR; // 525

    reg [9:0] h_cnt;  // 0..799
    reg [9:0] v_cnt;  // 0..524

    reg hsync_r, vsync_r;
    assign VGA_HS = hsync_r;
    assign VGA_VS = vsync_r;

    // One tick per frame at top-left pixel
    wire frame_tick = (h_cnt == 10'd0) && (v_cnt == 10'd0);

    always @(posedge pix_clk or posedge reset) begin
        if (reset) begin
            h_cnt   <= 10'd0;
            v_cnt   <= 10'd0;
            hsync_r <= 1'b1;
            vsync_r <= 1'b1;
        end else begin
            // Horizontal count
            if (h_cnt < H_TOTAL-1)
                h_cnt <= h_cnt + 10'd1;
            else begin
                h_cnt <= 10'd0;
                // Vertical count
                if (v_cnt < V_TOTAL-1)
                    v_cnt <= v_cnt + 10'd1;
                else
                    v_cnt <= 10'd0;
            end

            // HSYNC (active low)
            if (h_cnt >= (H_VISIBLE + H_FRONT_POR) &&
                h_cnt <  (H_VISIBLE + H_FRONT_POR + H_SYNC_PW))
                hsync_r <= 1'b0;
            else
                hsync_r <= 1'b1;

            // VSYNC (active low)
            if (v_cnt >= (V_VISIBLE + V_FRONT_POR) &&
                v_cnt <  (V_VISIBLE + V_FRONT_POR + V_SYNC_PW))
                vsync_r <= 1'b0;
            else
                vsync_r <= 1'b1;
        end
    end

    wire in_active_area = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);

    assign VGA_BLANK_N = in_active_area;
    assign VGA_SYNC_N  = 1'b0;

    // =========================================================
    // GAME TIMER & STATE (3 minutes)
    // =========================================================
    localparam [13:0] MAX_FRAMES = 14'd10800;
    localparam [13:0] TIME_33    = 14'd3600;
    localparam [13:0] TIME_66    = 14'd7200;

    reg [13:0] frame_counter;
    reg        game_active;
    reg        win;
    reg        lose;

    // =========================================================
    // GAME CONSTANTS & STATE
    // =========================================================

    // Keys: active low → active high
    //   btn[0] = red   (KEY3)
    //   btn[1] = yellow(KEY2)
    //   btn[2] = green (KEY1)
    //   btn[3] = blue  (KEY0)
    wire [3:0] btn = { ~KEY[0], ~KEY[1], ~KEY[2], ~KEY[3] };

    reg [3:0] prev_btn;

    // Lanes
    localparam L0_X_START = 40;   localparam L0_X_END = 160; // red
    localparam L1_X_START = 160;  localparam L1_X_END = 280; // yellow
    localparam L2_X_START = 280;  localparam L2_X_END = 400; // green
    localparam L3_X_START = 400;  localparam L3_X_END = 520; // blue

    // Hit window
    localparam HIT_Y_START  = 360;
    localparam HIT_Y_END    = 460;
    localparam HIT_Y_CENTER = (HIT_Y_START + HIT_Y_END) / 2;

    // Visual timing bands
    localparam PERF_HALF  = 3;
    localparam GOOD_HALF  = 10;

    // Notes
    localparam NOTE_HEIGHT = 32;

    // Score ranges
    localparam [7:0] SCORE_MAX   = 8'd255;
    localparam [7:0] SCORE_33    = 8'd85;
    localparam [7:0] SCORE_66    = 8'd170;
    localparam [7:0] SCORE_GOAL  = SCORE_MAX;

    // =========================================================
    // NOTE POOL
    // =========================================================
    localparam N_NOTES = 16;

    reg [9:0] note_y       [0:N_NOTES-1];
    reg [1:0] note_lane    [0:N_NOTES-1];
    reg       note_active  [0:N_NOTES-1];

    integer i, li;

    // Score & combo
    reg [7:0] score;
    reg [9:0] combo;
    reg [9:0] max_combo;      // not really used, but kept

    // Combo level: 0 = 0–9 hits (1.0x)
    //              1 = 10–19 hits (1.1x)
    //              2 = 20+ hits (1.2x)
    reg [1:0] combo_level;

    // Accuracy: 0 = miss/none, 1 = OK, 2 = good, 3 = perfect
    reg [1:0] last_judge;

    // Hit flash visuals
    reg [3:0] hit_flash;
    reg [3:0] hit_flash_timer [0:3];

    // Temp for judging
    reg [9:0] center_y;
    reg [9:0] diff;
    reg [1:0] judge;

    // Note speed based on score
    reg [3:0] note_speed;

    wire goal_req = (score >= SCORE_GOAL);

    // =========================================================
    // GLOBAL SPAWNER (lane pattern + repeats)
    // =========================================================
    reg [7:0] spawn_timer_global;
    reg [7:0] spawn_interval;

    reg [1:0] lane_sel;
    reg [1:0] last_lane;
    reg [1:0] streak_len;
    reg [3:0] prng;

    wire [1:0] candidate_lane =
        (prng[0] && (streak_len < 2)) ? last_lane : lane_sel;

    // =========================================================
    // GAME TIMER FSM
    // =========================================================
    always @(posedge pix_clk or posedge reset) begin
        if (reset) begin
            frame_counter <= 14'd0;
            game_active   <= 1'b1;
            win           <= 1'b0;
            lose          <= 1'b0;
        end else if (frame_tick) begin
            if (game_active) begin
                if (goal_req) begin
                    game_active <= 1'b0;
                    win         <= 1'b1;
                    lose        <= 1'b0;
                end else if (frame_counter < MAX_FRAMES) begin
                    frame_counter <= frame_counter + 14'd1;
                end else begin
                    game_active <= 1'b0;
                    win         <= 1'b0;
                    lose        <= 1'b1;
                end
            end
        end
    end

    // Note speed vs difficulty
    always @* begin
        if (!game_active) begin
            note_speed = 4'd0;
        end else if (score < SCORE_33) begin
            note_speed = 4'd2;   // easy
        end else if (score < SCORE_66) begin
            note_speed = 4'd4;   // medium
        end else begin
            note_speed = 4'd6;   // hard
        end
    end

    // Spawn interval vs difficulty
    always @* begin
        if (!game_active)
            spawn_interval = 8'd0;
        else if (score < SCORE_33)
            spawn_interval = 8'd28;
        else if (score < SCORE_66)
            spawn_interval = 8'd22;
        else
            spawn_interval = 8'd16;
    end

    // Combo level from combo count
    always @* begin
        if (combo >= 10'd20)
            combo_level = 2'd2;     // 1.2x
        else if (combo >= 10'd10)
            combo_level = 2'd1;     // 1.1x
        else
            combo_level = 2'd0;     // 1.0x
    end

    // =========================================================
    // GAME UPDATE: notes, hits, spawns
    // =========================================================
    always @(posedge pix_clk or posedge reset) begin : GAME_UPDATE
        integer free_idx;
        integer best_idx;
        reg     found_slot;
        reg     found;
        reg [9:0] best_diff;
        reg [9:0] local_center;
        reg [9:0] local_diff;

        // for combo-based scoring
        integer base_pts;
        integer mult;
        integer gain;

        if (reset) begin
            for (i = 0; i < N_NOTES; i = i + 1) begin
                note_y[i]      <= 10'd0;
                note_lane[i]   <= 2'd0;
                note_active[i] <= 1'b0;
            end

            for (li = 0; li < 4; li = li + 1) begin
                hit_flash[li]       <= 1'b0;
                hit_flash_timer[li] <= 4'd0;
            end

            score      <= 8'd0;
            combo      <= 10'd0;
            max_combo  <= 10'd0;
            last_judge <= 2'd0;
            prev_btn   <= 4'b0000;

            spawn_timer_global <= 8'd30;
            lane_sel           <= 2'd0;
            last_lane          <= 2'd0;
            streak_len         <= 2'd0;
            prng               <= 4'b1011;

        end else begin
            if (frame_tick && game_active) begin
                // Move notes and handle MISS (note falls off bottom)
                for (i = 0; i < N_NOTES; i = i + 1) begin
                    if (note_active[i]) begin
                        note_y[i] <= note_y[i] + note_speed;

                        if (note_y[i] > V_VISIBLE + NOTE_HEIGHT) begin
                            note_active[i] <= 1'b0;

                            // MISS penalty
                            last_judge <= 2'd0;
                            combo      <= 10'd0;   // reset combo on miss

                            if (score > 8'd2)
                                score <= score - 8'd2;
                            else
                                score <= 8'd0;
                        end
                    end
                end

                // Hit flash decay
                for (li = 0; li < 4; li = li + 1) begin
                    if (hit_flash[li]) begin
                        if (hit_flash_timer[li] > 0)
                            hit_flash_timer[li] <= hit_flash_timer[li] - 4'd1;
                        else
                            hit_flash[li] <= 1'b0;
                    end
                end

                // HIT / MIS-PRESS per lane
                for (li = 0; li < 4; li = li + 1) begin
                    if (btn[li] && !prev_btn[li]) begin
                        found     = 1'b0;
                        best_diff = 10'd1023;
                        best_idx  = 0;

                        // Find the closest note in this lane inside hit window
                        for (i = 0; i < N_NOTES; i = i + 1) begin
                            if (note_active[i] && (note_lane[i] == li)) begin
                                if ((note_y[i] + NOTE_HEIGHT) >= HIT_Y_START &&
                                    note_y[i] <= HIT_Y_END) begin

                                    local_center = note_y[i] + (NOTE_HEIGHT >> 1);
                                    if (local_center > HIT_Y_CENTER)
                                        local_diff = local_center - HIT_Y_CENTER;
                                    else
                                        local_diff = HIT_Y_CENTER - local_center;

                                    if (!found || (local_diff < best_diff)) begin
                                        found     = 1'b1;
                                        best_diff = local_diff;
                                        best_idx  = i;
                                    end
                                end
                            end
                        end

                        if (found) begin
                            // VALID HIT
                            if (best_diff <= 4)
                                judge = 2'd3;    // perfect
                            else if (best_diff <= 10)
                                judge = 2'd2;    // good
                            else
                                judge = 2'd1;    // ok

                            note_active[best_idx] <= 1'b0;
                            last_judge            <= judge;

                            // base points from accuracy
                            case (judge)
                                2'd3: base_pts = 2;  // perfect
                                2'd2: base_pts = 1;  // good
                                2'd1: base_pts = 0;  // ok
                                default: base_pts = 0;
                            endcase

                            // combo multiplier (1.0x, 1.1x, 1.2x)
                            case (combo_level)
                                2'd2: mult = 12; // 1.2x
                                2'd1: mult = 11; // 1.1x
                                default: mult = 10; // 1.0x
                            endcase

                            // gain = round(base_pts * mult / 10)
                            gain = (base_pts * mult + 5) / 10;

                            if (gain > 0) begin
                                if (score <= SCORE_MAX - gain[7:0])
                                    score <= score + gain[7:0];
                                else
                                    score <= SCORE_MAX;
                            end

                            // Update combo
                            if (combo < 10'd999)
                                combo <= combo + 10'd1;
                            if (combo > max_combo)
                                max_combo <= combo;

                            // flash lane
                            hit_flash[li]       <= 1'b1;
                            hit_flash_timer[li] <= 4'd8;

                        end else begin
                            // MIS-PRESS (no valid note in window)
                            last_judge <= 2'd0;
                            combo      <= 10'd0;   // reset combo

                            if (score > 8'd2)
                                score <= score - 8'd2;
                            else
                                score <= 8'd0;
                        end
                    end
                end

                prev_btn <= btn;

                // GLOBAL SPAWN
                prng <= {prng[2:0], prng[3] ^ prng[2]};

                if (spawn_timer_global > 0) begin
                    spawn_timer_global <= spawn_timer_global - 8'd1;
                end else begin
                    found_slot = 1'b0;
                    free_idx   = 0;

                    for (i = 0; i < N_NOTES; i = i + 1) begin
                        if (!note_active[i] && !found_slot) begin
                            found_slot = 1'b1;
                            free_idx   = i;
                        end
                    end

                    if (found_slot) begin
                        note_active[free_idx] <= 1'b1;
                        note_y[free_idx]      <= 10'd0;
                        note_lane[free_idx]   <= candidate_lane;

                        lane_sel <= lane_sel + 2'd1;

                        if (candidate_lane == last_lane) begin
                            if (streak_len < 2)
                                streak_len <= streak_len + 2'd1;
                        end else begin
                            last_lane  <= candidate_lane;
                            streak_len <= 2'd0;
                        end
                    end

                    spawn_timer_global <= spawn_interval;
                end
            end
        end
    end

    // =========================================================
    // AUDIO DISABLED
    // =========================================================
    assign pfm = 1'b0;

    // =========================================================
    // TIMER BAR (top of screen)
    // =========================================================
    wire [13:0] frames_left = (frame_counter >= MAX_FRAMES) ?
                              14'd0 : (MAX_FRAMES - frame_counter);

    wire [23:0] time_mult    = frames_left * H_VISIBLE;
    wire [9:0]  time_bar_len = time_mult / MAX_FRAMES;

    // Combo bar height (saturate to screen height)
    wire [8:0] combo_height = (combo > 9'd479) ? 9'd479 : combo[8:0];

    // =========================================================
    // PIXEL GENERATION
    // =========================================================
    reg [7:0] R_pix;
    reg [7:0] G_pix;
    reg [7:0] B_pix;

    // Lane X flags
    wire in_lane0_x = (h_cnt >= L0_X_START) && (h_cnt < L0_X_END);
    wire in_lane1_x = (h_cnt >= L1_X_START) && (h_cnt < L1_X_END);
    wire in_lane2_x = (h_cnt >= L2_X_START) && (h_cnt < L2_X_END);
    wire in_lane3_x = (h_cnt >= L3_X_START) && (h_cnt < L3_X_END);

    // Hit window flags
    wire in_hit_bar_y   = (v_cnt >= HIT_Y_START) && (v_cnt < HIT_Y_END);
    wire in_good_zone_y = (v_cnt >= (HIT_Y_CENTER - GOOD_HALF)) &&
                          (v_cnt <= (HIT_Y_CENTER + GOOD_HALF));
    wire in_perf_zone_y = (v_cnt >= (HIT_Y_CENTER - PERF_HALF)) &&
                          (v_cnt <= (HIT_Y_CENTER + PERF_HALF));

    reg [7:0] ER, EG, EB; // "END" colors
    integer   draw_i;

    always @* begin
        // default background
        R_pix = 8'd10;
        G_pix = 8'd10;
        B_pix = 8'd10;

        if (!in_active_area) begin
            R_pix = 8'd0;
            G_pix = 8'd0;
            B_pix = 8'd0;
        end else if (!game_active) begin
            // END SCREEN
            R_pix = 8'd0;
            G_pix = 8'd0;
            B_pix = 8'd0;

            if (win || lose) begin
                if (win) begin
                    ER = 8'd0;   EG = 8'd255; EB = 8'd0;
                end else begin
                    ER = 8'd255; EG = 8'd0;   EB = 8'd0;
                end

                // 'E'
                if ((h_cnt >= 160 && h_cnt < 190 && v_cnt >= 160 && v_cnt < 320) ||
                    (h_cnt >= 190 && h_cnt < 230 && v_cnt >= 160 && v_cnt < 180) ||
                    (h_cnt >= 190 && h_cnt < 220 && v_cnt >= 230 && v_cnt < 250) ||
                    (h_cnt >= 190 && h_cnt < 230 && v_cnt >= 300 && v_cnt < 320)) begin
                    R_pix = ER; G_pix = EG; B_pix = EB;
                end

                // 'N'
                if ((h_cnt >= 250 && h_cnt < 270 && v_cnt >= 160 && v_cnt < 320) ||
                    (h_cnt >= 290 && h_cnt < 310 && v_cnt >= 160 && v_cnt < 320) ||
                    ((h_cnt >= 270 && h_cnt < 290) &&
                     (v_cnt + h_cnt >= 430) && (v_cnt + h_cnt <= 450))) begin
                    R_pix = ER; G_pix = EG; B_pix = EB;
                end

                // 'D'
                if ((h_cnt >= 330 && h_cnt < 350 && v_cnt >= 160 && v_cnt < 320) ||
                    (h_cnt >= 350 && h_cnt < 390 && v_cnt >= 160 && v_cnt < 180) ||
                    (h_cnt >= 350 && h_cnt < 390 && v_cnt >= 300 && v_cnt < 320) ||
                    (h_cnt >= 390 && h_cnt < 410 && v_cnt >= 180 && v_cnt < 300)) begin
                    R_pix = ER; G_pix = EG; B_pix = EB;
                end
            end

        end else begin
            // ACTIVE GAME

            // Lane backgrounds
            if (in_lane0_x) begin
                R_pix = 8'd40; G_pix = 8'd0;  B_pix = 8'd0;
            end
            if (in_lane1_x) begin
                R_pix = 8'd40; G_pix = 8'd40; B_pix = 8'd0;
            end
            if (in_lane2_x) begin
                R_pix = 8'd0;  G_pix = 8'd40; B_pix = 8'd0;
            end
            if (in_lane3_x) begin
                R_pix = 8'd0;  G_pix = 8'd0;  B_pix = 8'd40;
            end

            // Timing bands
            if (in_hit_bar_y) begin
                R_pix = 8'd30; G_pix = 8'd30; B_pix = 8'd60;   // OK
                if (in_good_zone_y) begin
                    R_pix = 8'd200; G_pix = 8'd200; B_pix = 8'd40; // GOOD
                end
                if (in_perf_zone_y) begin
                    R_pix = 8'd255; G_pix = 8'd255; B_pix = 8'd255; // PERFECT
                end
            end

            // Draw all active notes
            for (draw_i = 0; draw_i < N_NOTES; draw_i = draw_i + 1) begin
                if (note_active[draw_i] &&
                    (v_cnt >= note_y[draw_i]) &&
                    (v_cnt <  note_y[draw_i] + NOTE_HEIGHT)) begin

                    case (note_lane[draw_i])
                        2'd0: if (in_lane0_x) begin
                            R_pix = 8'd255; G_pix = 8'd0;   B_pix = 8'd0;
                        end
                        2'd1: if (in_lane1_x) begin
                            R_pix = 8'd255; G_pix = 8'd255; B_pix = 8'd0;
                        end
                        2'd2: if (in_lane2_x) begin
                            R_pix = 8'd0;   G_pix = 8'd255; B_pix = 8'd0;
                        end
                        2'd3: if (in_lane3_x) begin
                            R_pix = 8'd0;   G_pix = 8'd0;   B_pix = 8'd255;
                        end
                    endcase
                end
            end

            // Score bar (right side)
            if (h_cnt >= 580 && h_cnt < 600) begin
                if (v_cnt >= (V_VISIBLE - score)) begin
                    case (last_judge)
                        2'd3: begin
                            R_pix = 8'd255; G_pix = 8'd80;  B_pix = 8'd255; // perfect
                        end
                        2'd2: begin
                            R_pix = 8'd80;  G_pix = 8'd255; B_pix = 8'd255; // good
                        end
                        2'd1: begin
                            R_pix = 8'd80;  G_pix = 8'd255; B_pix = 8'd80;  // ok
                        end
                        default: begin
                            R_pix = 8'd40;  G_pix = 8'd40;  B_pix = 8'd40;  // miss
                        end
                    endcase
                end

                // Horizontal marker at 100% (top of score bar)
                if (v_cnt == (V_VISIBLE - SCORE_MAX)) begin
                    R_pix = 8'd255;
                    G_pix = 8'd255;
                    B_pix = 8'd255;
                end
            end

            // Combo bar (left side, x ~10–20) with color by combo level
            if (h_cnt >= 10 && h_cnt < 20) begin
                if (v_cnt >= (V_VISIBLE - combo_height)) begin
                    case (combo_level)
                        2'd2: begin
                            // high combo: bright gold
                            R_pix = 8'd255; G_pix = 8'd215; B_pix = 8'd0;
                        end
                        2'd1: begin
                            // mid combo: yellow-green
                            R_pix = 8'd200; G_pix = 8'd255; B_pix = 8'd0;
                        end
                        default: begin
                            // low combo: soft green
                            R_pix = 8'd80;  G_pix = 8'd200; B_pix = 8'd80;
                        end
                    endcase
                end
            end

            // Lane hit-flash overlay in hit window
            if (in_hit_bar_y) begin
                if (hit_flash[0] && in_lane0_x) begin
                    R_pix = 8'd255; G_pix = 8'd150; B_pix = 8'd150;
                end
                if (hit_flash[1] && in_lane1_x) begin
                    R_pix = 8'd255; G_pix = 8'd255; B_pix = 8'd150;
                end
                if (hit_flash[2] && in_lane2_x) begin
                    R_pix = 8'd150; G_pix = 8'd255; B_pix = 8'd150;
                end
                if (hit_flash[3] && in_lane3_x) begin
                    R_pix = 8'd150; G_pix = 8'd150; B_pix = 8'd255;
                end
            end

            // Top time bar
            if ((v_cnt >= 5) && (v_cnt < 15) && (h_cnt < time_bar_len)) begin
                if (frames_left > TIME_66) begin
                    R_pix = 8'd0;   G_pix = 8'd255; B_pix = 8'd0;
                end else if (frames_left > TIME_33) begin
                    R_pix = 8'd255; G_pix = 8'd255; B_pix = 8'd0;
                end else begin
                    R_pix = 8'd255; G_pix = 8'd0;   B_pix = 8'd0;
                end
            end
        end
    end

    assign VGA_R = R_pix;
    assign VGA_G = G_pix;
    assign VGA_B = B_pix;

    // =========================================================
    // LEDs
    // =========================================================
    assign LEDR[3:0] = btn;          // show button presses
    assign LEDR[7:4] = combo[7:4];   // upper bits of combo
    assign LEDR[8]   = pix_clk;
    assign LEDR[9]   = CLOCK_50;

endmodule
