[1].map(x => { switch (x) { case 1: return x; default: throw new Error(); } });
[1].map(x => { switch (x) { case 1: if (x > 1) break; return x; default: return 0; } });
