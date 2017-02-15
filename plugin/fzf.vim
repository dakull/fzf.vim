"" Copyright (c) 2016 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

let s:default_layout = { 'down': '~40%' }
let s:layout_keys = ['window', 'up', 'down', 'left', 'right']
let s:fzf_go = expand('<sfile>:h:h').'/bin/fzf'
let s:install = expand('<sfile>:h:h').'/install'
let s:installed = 0
let s:fzf_tmux = expand('<sfile>:h:h').'/bin/fzf-tmux'

let s:cpo_save = &cpo
set cpo&vim

function! s:fzf_exec()
  if !exists('s:exec')
    if executable(s:fzf_go)
      let s:exec = s:fzf_go
    elseif executable('fzf')
      let s:exec = 'fzf'
    elseif !s:installed && executable(s:install) &&
          \ input('fzf executable not found. Download binary? (y/n) ') =~? '^y'
      redraw
      echo
      call s:warn('Downloading fzf binary. Please wait ...')
      let s:installed = 1
      call system(s:install.' --bin')
      return s:fzf_exec()
    else
      redraw
      throw 'fzf executable not found'
    endif
  endif
  return s:shellesc(s:exec)
endfunction

function! s:tmux_enabled()
  if has('gui_running')
    return 0
  endif

  if exists('s:tmux')
    return s:tmux
  endif

  let s:tmux = 0
  if exists('$TMUX') && executable(s:fzf_tmux)
    let output = system('tmux -V')
    let s:tmux = !v:shell_error && output >= 'tmux 1.7'
  endif
  return s:tmux
endfunction

function! s:shellesc(arg)
  return '"'.substitute(a:arg, '"', '\\"', 'g').'"'
endfunction

function! s:escape(path)
  return escape(a:path, ' $%#''"\')
endfunction

" Upgrade legacy options
function! s:upgrade(dict)
  let copy = copy(a:dict)
  if has_key(copy, 'tmux')
    let copy.down = remove(copy, 'tmux')
  endif
  if has_key(copy, 'tmux_height')
    let copy.down = remove(copy, 'tmux_height')
  endif
  if has_key(copy, 'tmux_width')
    let copy.right = remove(copy, 'tmux_width')
  endif
  return copy
endfunction

function! s:error(msg)
  echohl ErrorMsg
  echom a:msg
  echohl None
endfunction

function! s:warn(msg)
  echohl WarningMsg
  echom a:msg
  echohl None
endfunction

function! s:has_any(dict, keys)
  for key in a:keys
    if has_key(a:dict, key)
      return 1
    endif
  endfor
  return 0
endfunction

function! s:open(cmd, target)
  if stridx('edit', a:cmd) == 0 && fnamemodify(a:target, ':p') ==# expand('%:p')
    return
  endif
  execute a:cmd s:escape(a:target)
endfunction

function! s:common_sink(action, lines) abort
  if len(a:lines) < 2
    return
  endif
  let key = remove(a:lines, 0)
  let cmd = get(a:action, key, 'e')
  if len(a:lines) > 1
    augroup fzf_swap
      autocmd SwapExists * let v:swapchoice='o'
            \| call s:warn('fzf: E325: swap file exists: '.expand('<afile>'))
    augroup END
  endif
  try
    let empty = empty(expand('%')) && line('$') == 1 && empty(getline(1)) && !&modified
    let autochdir = &autochdir
    set noautochdir
    for item in a:lines
      if empty
        execute 'e' s:escape(item)
        let empty = 0
      else
        call s:open(cmd, item)
      endif
      if exists('#BufEnter') && isdirectory(item)
        doautocmd BufEnter
      endif
    endfor
  finally
    let &autochdir = autochdir
    silent! autocmd! fzf_swap
  endtry
endfunction

" [name string,] [opts dict,] [fullscreen boolean]
function! fzf#wrap(...)
  let args = ['', {}, 0]
  let expects = map(copy(args), 'type(v:val)')
  let tidx = 0
  for arg in copy(a:000)
    let tidx = index(expects, type(arg), tidx)
    if tidx < 0
      throw 'invalid arguments (expected: [name string] [opts dict] [fullscreen boolean])'
    endif
    let args[tidx] = arg
    let tidx += 1
    unlet arg
  endfor
  let [name, opts, bang] = args

  " Layout: g:fzf_layout (and deprecated g:fzf_height)
  if bang
    for key in s:layout_keys
      if has_key(opts, key)
        call remove(opts, key)
      endif
    endfor
  elseif !s:has_any(opts, s:layout_keys)
    if !exists('g:fzf_layout') && exists('g:fzf_height')
      let opts.down = g:fzf_height
    else
      let opts = extend(opts, get(g:, 'fzf_layout', s:default_layout))
    endif
  endif

  " History: g:fzf_history_dir
  let opts.options = get(opts, 'options', '')
  if len(name) && len(get(g:, 'fzf_history_dir', ''))
    let dir = expand(g:fzf_history_dir)
    if !isdirectory(dir)
      call mkdir(dir, 'p')
    endif
    let opts.options = join(['--history', s:escape(dir.'/'.name), opts.options])
  endif

  " Action: g:fzf_action
  if !s:has_any(opts, ['sink', 'sink*'])
    let opts._action = get(g:, 'fzf_action', s:default_action)
    let opts.options .= ' --expect='.join(keys(opts._action), ',')
    function! opts.sink(lines) abort
      return s:common_sink(self._action, a:lines)
    endfunction
    let opts['sink*'] = remove(opts, 'sink')
  endif

  return opts
endfunction

function! fzf#run(...) abort
try
  let oshell = &shell
  set shell=sh
  if has('nvim') && len(filter(range(1, bufnr('$')), 'bufname(v:val) =~# ";#FZF"'))
    call s:warn('FZF is already running!')
    return []
  endif
  let dict   = exists('a:1') ? s:upgrade(a:1) : {}
  let temps  = { 'result': tempname() }
  let optstr = get(dict, 'options', '')
  try
    let fzf_exec = s:fzf_exec()
  catch
    throw v:exception
  endtry

  if !has_key(dict, 'source') && !empty($FZF_DEFAULT_COMMAND)
    let temps.source = tempname()
    call writefile(split($FZF_DEFAULT_COMMAND, "\n"), temps.source)
    let dict.source = (empty($SHELL) ? 'sh' : $SHELL) . ' ' . s:shellesc(temps.source)
  endif

  if has_key(dict, 'source')
    let source = dict.source
    let type = type(source)
    if type == 1
      let prefix = source.'|'
    elseif type == 3
      let temps.input = tempname()
      call writefile(source, temps.input)
      let prefix = 'cat '.s:shellesc(temps.input).'|'
    else
      throw 'invalid source type'
    endif
  else
    let prefix = ''
  endif
  let tmux = (!has('nvim') || get(g:, 'fzf_prefer_tmux', 0)) && s:tmux_enabled() && s:splittable(dict)
  let command = prefix.(tmux ? s:fzf_tmux(dict) : fzf_exec).' '.optstr.' > '.temps.result

  if has('nvim') && !tmux
    return s:execute_term(dict, command, temps)
  endif

  let lines = tmux ? s:execute_tmux(dict, command, temps) : s:execute(dict, command, temps)
  call s:callback(dict, lines)
  return lines
finally
  let &shell = oshell
endtry
endfunction

function! s:present(dict, ...)
  for key in a:000
    if !empty(get(a:dict, key, ''))
      return 1
    endif
  endfor
  return 0
endfunction

function! s:fzf_tmux(dict)
  let size = ''
  for o in ['up', 'down', 'left', 'right']
    if s:present(a:dict, o)
      let spec = a:dict[o]
      if (o == 'up' || o == 'down') && spec[0] == '~'
        let size = '-'.o[0].s:calc_size(&lines, spec, a:dict)
      else
        " Legacy boolean option
        let size = '-'.o[0].(spec == 1 ? '' : substitute(spec, '^\~', '', ''))
      endif
      break
    endif
  endfor
  return printf('LINES=%d COLUMNS=%d %s %s %s --',
    \ &lines, &columns, s:shellesc(s:fzf_tmux), size, (has_key(a:dict, 'source') ? '' : '-'))
endfunction

function! s:splittable(dict)
  return s:present(a:dict, 'up', 'down', 'left', 'right')
endfunction

function! s:pushd(dict)
  if s:present(a:dict, 'dir')
    let cwd = getcwd()
    if get(a:dict, 'prev_dir', '') ==# cwd
      return 1
    endif
    let a:dict.prev_dir = cwd
    execute 'lcd' s:escape(a:dict.dir)
    let a:dict.dir = getcwd()
    return 1
  endif
  return 0
endfunction

augroup fzf_popd
  autocmd!
  autocmd WinEnter * call s:dopopd()
augroup END

function! s:dopopd()
  if !exists('w:fzf_prev_dir') || exists('*haslocaldir') && !haslocaldir()
    return
  endif
  execute 'lcd' s:escape(w:fzf_prev_dir)
  unlet w:fzf_prev_dir
endfunction

function! s:xterm_launcher()
  let fmt = 'xterm -T "[fzf]" -bg "\%s" -fg "\%s" -geometry %dx%d+%d+%d -e bash -ic %%s'
  if has('gui_macvim')
    let fmt .= '&& osascript -e "tell application \"MacVim\" to activate"'
  endif
  return printf(fmt,
    \ synIDattr(hlID("Normal"), "bg"), synIDattr(hlID("Normal"), "fg"),
    \ &columns, &lines/2, getwinposx(), getwinposy())
endfunction
unlet! s:launcher
let s:launcher = function('s:xterm_launcher')

function! s:exit_handler(code, command, ...)
  if a:code == 130
    return 0
  elseif a:code > 1
    call s:error('Error running ' . a:command)
    if !empty(a:000)
      sleep
    endif
    return 0
  endif
  return 1
endfunction

function! s:execute(dict, command, temps) abort
  call s:pushd(a:dict)
  silent! !clear 2> /dev/null
  let escaped = escape(substitute(a:command, '\n', '\\n', 'g'), '%#')
  if has('gui_running')
    let Launcher = get(a:dict, 'launcher', get(g:, 'Fzf_launcher', get(g:, 'fzf_launcher', s:launcher)))
    let fmt = type(Launcher) == 2 ? call(Launcher, []) : Launcher
    let command = printf(fmt, "'".substitute(escaped, "'", "'\"'\"'", 'g')."'")
  else
    let command = escaped
  endif
  execute 'silent !'.command
  let exit_status = v:shell_error
  redraw!
  return s:exit_handler(exit_status, command) ? s:collect(a:temps) : []
endfunction

function! s:execute_tmux(dict, command, temps) abort
  let command = a:command
  if s:pushd(a:dict)
    " -c '#{pane_current_path}' is only available on tmux 1.9 or above
    let command = 'cd '.s:escape(a:dict.dir).' && '.command
  endif

  call system(command)
  let exit_status = v:shell_error
  redraw!
  return s:exit_handler(exit_status, command) ? s:collect(a:temps) : []
endfunction

function! s:calc_size(max, val, dict)
  let val = substitute(a:val, '^\~', '', '')
  if val =~ '%$'
    let size = a:max * str2nr(val[:-2]) / 100
  else
    let size = min([a:max, str2nr(val)])
  endif

  let srcsz = -1
  if type(get(a:dict, 'source', 0)) == type([])
    let srcsz = len(a:dict.source)
  endif

  let opts = get(a:dict, 'options', '').$FZF_DEFAULT_OPTS
  let margin = stridx(opts, '--inline-info') > stridx(opts, '--no-inline-info') ? 1 : 2
  let margin += stridx(opts, '--header') > stridx(opts, '--no-header')
  return srcsz >= 0 ? min([srcsz + margin, size]) : size
endfunction

function! s:getpos()
  return {'tab': tabpagenr(), 'win': winnr(), 'cnt': winnr('$'), 'tcnt': tabpagenr('$')}
endfunction

function! s:split(dict)
  let directions = {
  \ 'up':    ['topleft', 'resize', &lines],
  \ 'down':  ['botright', 'resize', &lines],
  \ 'left':  ['vertical topleft', 'vertical resize', &columns],
  \ 'right': ['vertical botright', 'vertical resize', &columns] }
  let ppos = s:getpos()
  try
    for [dir, triple] in items(directions)
      let val = get(a:dict, dir, '')
      if !empty(val)
        let [cmd, resz, max] = triple
        if (dir == 'up' || dir == 'down') && val[0] == '~'
          let sz = s:calc_size(max, val, a:dict)
        else
          let sz = s:calc_size(max, val, {})
        endif
        execute cmd sz.'new'
        execute resz sz
        return [ppos, {}]
      endif
    endfor
    if s:present(a:dict, 'window')
      execute a:dict.window
    else
      execute (tabpagenr()-1).'tabnew'
    endif
    return [ppos, { '&l:wfw': &l:wfw, '&l:wfh': &l:wfh }]
  finally
    setlocal winfixwidth winfixheight
  endtry
endfunction

function! s:execute_term(dict, command, temps) abort
  let winrest = winrestcmd()
  let [ppos, winopts] = s:split(a:dict)
  let fzf = { 'buf': bufnr('%'), 'ppos': ppos, 'dict': a:dict, 'temps': a:temps,
            \ 'winopts': winopts, 'winrest': winrest, 'lines': &lines,
            \ 'columns': &columns, 'command': a:command }
  function! fzf.switch_back(inplace)
    if a:inplace && bufnr('') == self.buf
      " FIXME: Can't re-enter normal mode from terminal mode
      " execute "normal! \<c-^>"
      b #
      " No other listed buffer
      if bufnr('') == self.buf
        enew
      endif
    endif
  endfunction
  function! fzf.on_exit(id, code)
    if s:getpos() == self.ppos " {'window': 'enew'}
      for [opt, val] in items(self.winopts)
        execute 'let' opt '=' val
      endfor
      call self.switch_back(1)
    else
      if bufnr('') == self.buf
        " We use close instead of bd! since Vim does not close the split when
        " there's no other listed buffer (nvim +'set nobuflisted')
        close
      endif
      execute 'tabnext' self.ppos.tab
      execute self.ppos.win.'wincmd w'
    endif

    if bufexists(self.buf)
      execute 'bd!' self.buf
    endif

    if &lines == self.lines && &columns == self.columns && s:getpos() == self.ppos
      execute self.winrest
    endif

    if !s:exit_handler(a:code, self.command, 1)
      return
    endif

    call s:pushd(self.dict)
    let lines = s:collect(self.temps)
    call s:callback(self.dict, lines)
    call self.switch_back(s:getpos() == self.ppos)
  endfunction

  try
    if s:present(a:dict, 'dir')
      execute 'lcd' s:escape(a:dict.dir)
    endif
    call termopen(a:command . ';#FZF', fzf)
  finally
    if s:present(a:dict, 'dir')
      lcd -
    endif
  endtry
  setlocal nospell bufhidden=wipe nobuflisted
  setf fzf
  startinsert
  return []
endfunction

function! s:collect(temps) abort
  try
    return filereadable(a:temps.result) ? readfile(a:temps.result) : []
  finally
    for tf in values(a:temps)
      silent! call delete(tf)
    endfor
  endtry
endfunction

function! s:callback(dict, lines) abort
  " Since anything can be done in the sink function, there is no telling that
  " the change of the working directory was made by &autochdir setting.
  "
  " We use the following heuristic to determine whether to restore CWD:
  " - Always restore the current directory when &autochdir is disabled.
  "   FIXME This makes it impossible to change directory from inside the sink
  "   function when &autochdir is not used.
  " - In case of an error or an interrupt, a:lines will be empty.
  "   And it will be an array of a single empty string when fzf was finished
  "   without a match. In these cases, we presume that the change of the
  "   directory is not expected and should be undone.
  let popd = has_key(a:dict, 'prev_dir') &&
        \ (!&autochdir || (empty(a:lines) || len(a:lines) == 1 && empty(a:lines[0])))
  if popd
    let w:fzf_prev_dir = a:dict.prev_dir
  endif

  try
    if has_key(a:dict, 'sink')
      for line in a:lines
        if type(a:dict.sink) == 2
          call a:dict.sink(line)
        else
          execute a:dict.sink s:escape(line)
        endif
      endfor
    endif
    if has_key(a:dict, 'sink*')
      call a:dict['sink*'](a:lines)
    endif
  catch
    if stridx(v:exception, ':E325:') < 0
      echoerr v:exception
    endif
  endtry

  " We may have opened a new window or tab
  if popd
    let w:fzf_prev_dir = a:dict.prev_dir
    call s:dopopd()
  endif
endfunction

let s:default_action = {
  \ 'ctrl-t': 'tab split',
  \ 'ctrl-x': 'split',
  \ 'ctrl-v': 'vsplit' }

function! s:cmd(bang, ...) abort
  let args = copy(a:000)
  let opts = {}
  if len(args) && isdirectory(expand(args[-1]))
    let opts.dir = substitute(remove(args, -1), '\\\(["'']\)', '\1', 'g')
  endif
  call fzf#run(fzf#wrap('FZF', extend({'options': join(args)}, opts), a:bang))
endfunction

command! -nargs=* -complete=dir -bang FZF call s:cmd(<bang>0, <f-args>)

let &cpo = s:cpo_save
unlet s:cpo_save
"
"
" 
" Copyright (c) 2015 Junegunn Choi
"
" MIT License
"
" Permission is hereby granted, free of charge, to any person obtaining
" a copy of this software and associated documentation files (the
" "Software"), to deal in the Software without restriction, including
" without limitation the rights to use, copy, modify, merge, publish,
" distribute, sublicense, and/or sell copies of the Software, and to
" permit persons to whom the Software is furnished to do so, subject to
" the following conditions:
"
" The above copyright notice and this permission notice shall be
" included in all copies or substantial portions of the Software.
"
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
" EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
" MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
" NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
" LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
" OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
" WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

let s:cpo_save = &cpo
set cpo&vim

let g:fzf#vim#default_layout = {'down': '~40%'}

function! s:defs(commands)
  let prefix = get(g:, 'fzf_command_prefix', '')
  if prefix =~# '^[^A-Z]'
    echoerr 'g:fzf_command_prefix must start with an uppercase letter'
    return
  endif
  for command in a:commands
    execute substitute(command, '\ze\C[A-Z]', prefix, '')
  endfor
endfunction

call s:defs([
\'command! -bang -nargs=? -complete=dir Files  call fzf#vim#files(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=? GitFiles             call fzf#vim#gitfiles(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=? GFiles               call fzf#vim#gitfiles(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang Buffers                       call fzf#vim#buffers(fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* Lines                call fzf#vim#lines(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* BLines               call fzf#vim#buffer_lines(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang Colors                        call fzf#vim#colors(fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=1 -complete=dir Locate call fzf#vim#locate(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* Ag                   call fzf#vim#ag(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* Tags                 call fzf#vim#tags(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* BTags                call fzf#vim#buffer_tags(<q-args>, fzf#vim#layout(<bang>0))',
\'command! -bang Snippets                      call fzf#vim#snippets(fzf#vim#layout(<bang>0))',
\'command! -bang Commands                      call fzf#vim#commands(fzf#vim#layout(<bang>0))',
\'command! -bang Marks                         call fzf#vim#marks(fzf#vim#layout(<bang>0))',
\'command! -bang Helptags                      call fzf#vim#helptags(fzf#vim#layout(<bang>0))',
\'command! -bang Windows                       call fzf#vim#windows(fzf#vim#layout(<bang>0))',
\'command! -bang Commits                       call fzf#vim#commits(fzf#vim#layout(<bang>0))',
\'command! -bang BCommits                      call fzf#vim#buffer_commits(fzf#vim#layout(<bang>0))',
\'command! -bang Maps                          call fzf#vim#maps("n", fzf#vim#layout(<bang>0))',
\'command! -bang Filetypes                     call fzf#vim#filetypes(fzf#vim#layout(<bang>0))',
\'command! -bang -nargs=* History              call s:history(<q-args>, <bang>0)'])

function! s:history(arg, bang)
  let bang = a:bang || a:arg[len(a:arg)-1] == '!'
  let ext = fzf#vim#layout(bang)
  if a:arg[0] == ':'
    call fzf#vim#command_history(ext)
  elseif a:arg[0] == '/'
    call fzf#vim#search_history(ext)
  else
    call fzf#vim#history(ext)
  endif
endfunction

function! fzf#complete(...)
  return call('fzf#vim#complete', a:000)
endfunction

if has('nvim') && get(g:, 'fzf_nvim_statusline', 1)
  function! s:fzf_restore_colors()
    if exists('#User#FzfStatusLine')
      doautocmd User FzfStatusLine
    else
      if $TERM !~ "256color"
        highlight fzf1 ctermfg=1 ctermbg=8 guifg=#E12672 guibg=#565656
        highlight fzf2 ctermfg=2 ctermbg=8 guifg=#BCDDBD guibg=#565656
        highlight fzf3 ctermfg=7 ctermbg=8 guifg=#D9D9D9 guibg=#565656
      else
        highlight fzf1 ctermfg=161 ctermbg=238 guifg=#E12672 guibg=#565656
        highlight fzf2 ctermfg=151 ctermbg=238 guifg=#BCDDBD guibg=#565656
        highlight fzf3 ctermfg=252 ctermbg=238 guifg=#D9D9D9 guibg=#565656
      endif
      setlocal statusline=%#fzf1#\ >\ %#fzf2#fz%#fzf3#f
    endif
  endfunction

  function! s:fzf_nvim_term()
    if get(w:, 'airline_active', 0)
      let w:airline_disabled = 1
      autocmd BufWinLeave <buffer> let w:airline_disabled = 0
    endif
    autocmd WinEnter,ColorScheme <buffer> call s:fzf_restore_colors()

    setlocal nospell
    call s:fzf_restore_colors()
  endfunction

  augroup _fzf_statusline
    autocmd!
    autocmd FileType fzf call s:fzf_nvim_term()
  augroup END
endif

let g:fzf#vim#buffers = {}
augroup fzf_buffers
  autocmd!
  if exists('*reltimefloat')
    autocmd BufWinEnter,WinEnter * let g:fzf#vim#buffers[bufnr('')] = reltimefloat(reltime())
  else
    autocmd BufWinEnter,WinEnter * let g:fzf#vim#buffers[bufnr('')] = localtime()
  endif
  autocmd BufDelete * silent! call remove(g:fzf#vim#buffers, expand('<abuf>'))
augroup END

inoremap <expr> <plug>(fzf-complete-word)        fzf#vim#complete#word()
inoremap <expr> <plug>(fzf-complete-path)        fzf#vim#complete#path("find . -path '*/\.*' -prune -o -print \| sed '1d;s:^..::'")
inoremap <expr> <plug>(fzf-complete-file)        fzf#vim#complete#path("find . -path '*/\.*' -prune -o -type f -print -o -type l -print \| sed 's:^..::'")
inoremap <expr> <plug>(fzf-complete-file-ag)     fzf#vim#complete#path("ag -l -g ''")
inoremap <expr> <plug>(fzf-complete-line)        fzf#vim#complete#line()
inoremap <expr> <plug>(fzf-complete-buffer-line) fzf#vim#complete#buffer_line()

nnoremap <silent> <plug>(fzf-maps-n) :<c-u>call fzf#vim#maps('n', fzf#vim#layout(0))<cr>
inoremap <silent> <plug>(fzf-maps-i) <c-o>:call fzf#vim#maps('i', fzf#vim#layout(0))<cr>
xnoremap <silent> <plug>(fzf-maps-x) :<c-u>call fzf#vim#maps('x', fzf#vim#layout(0))<cr>
onoremap <silent> <plug>(fzf-maps-o) <c-c>:<c-u>call fzf#vim#maps('o', fzf#vim#layout(0))<cr>

let &cpo = s:cpo_save
unlet s:cpo_save

